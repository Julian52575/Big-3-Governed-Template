#!/usr/bin/env bash
# Turn the analysis that SonarSource/sonarqube-scan-action just uploaded into a
# small, branch-local record under .sast/report/sonarqube/ .
#
# Produces (ci-sast.yml's commit-reports job commits these to main on push):
#   measures.json      raw metric values from the SonarQube Cloud API
#   quality-gate.json  raw Quality Gate status + any failing conditions
#   summary.md         human-readable digest -- also written to the run summary
#   badge.svg          gate badge, referenced by README.md via a relative path
#
# Inputs (env):
#   SONAR_TOKEN          analysis token; also used for the read-only API calls
#   SONAR_SCOPE          "branch=<name>" or "pullRequest=<number>"
#   GITHUB_STEP_SUMMARY  optional; summary.md is appended to it when set
#   GITHUB_OUTPUT        optional; "gate=passed|warning|failed|unknown" written
#
# Reads .scannerwork/report-task.txt (written by the scan) for the server URL,
# project key and background-task URL.
set -euo pipefail

meta=.scannerwork/report-task.txt
[[ -f $meta ]] || { echo "::error::$meta not found -- did the SonarQube scan run?"; exit 1; }

host=$(sed -n 's/^serverUrl=//p'    "$meta" | tr -d '\r')
project=$(sed -n 's/^projectKey=//p' "$meta" | tr -d '\r')
task_url=$(sed -n 's/^ceTaskUrl=//p' "$meta" | tr -d '\r')
report_dir=.sast/report/sonarqube
mkdir -p "$report_dir"

auth=()
[[ -n ${SONAR_TOKEN:-} ]] && auth=(-u "${SONAR_TOKEN}:")
api() { curl -sSf --retry 3 --retry-delay 2 --retry-all-errors "${auth[@]}" "$@"; }

# --- wait for SonarQube Cloud to finish processing the upload ------------
analysis_id=""
for _ in $(seq 1 60); do
  task=$(api "$task_url")
  case $(jq -r '.task.status' <<<"$task") in
    SUCCESS)         analysis_id=$(jq -r '.task.analysisId' <<<"$task"); break ;;
    FAILED|CANCELED) echo "::error::SonarQube background task did not succeed"; exit 1 ;;
    *)               sleep 5 ;;
  esac
done
[[ -n $analysis_id ]] || { echo "::error::timed out waiting for the SonarQube analysis"; exit 1; }

scope=()
[[ -n ${SONAR_SCOPE:-} ]] && scope=(--data-urlencode "$SONAR_SCOPE")

# --- pull the numbers --------------------------------------------------
metrics=alert_status,bugs,vulnerabilities,security_hotspots,code_smells,coverage,duplicated_lines_density,ncloc,reliability_rating,security_rating,sqale_rating
api -G "$host/api/measures/component" \
    --data-urlencode "component=$project" \
    --data-urlencode "metricKeys=$metrics" \
    "${scope[@]}" | jq '.' > "$report_dir/measures.json"

api -G "$host/api/qualitygates/project_status" \
    --data-urlencode "projectKey=$project" \
    "${scope[@]}" | jq '.' > "$report_dir/quality-gate.json"

# --- shape it --------------------------------------------------------
m() { jq -r --arg k "$1" '.component.measures[]? | select(.metric==$k) | .value' "$report_dir/measures.json"; }
rating() { case "${1%%.*}" in 1) echo A;; 2) echo B;; 3) echo C;; 4) echo D;; 5) echo E;; *) echo "?";; esac; }

gate=$(jq -r '.projectStatus.status' "$report_dir/quality-gate.json")
case "$gate" in
  OK)    verdict=passed;  colour="#4c1";    icon="white_check_mark" ;;
  WARN)  verdict=warning; colour="#dfb317"; icon="warning" ;;
  ERROR) verdict=failed;  colour="#e05d44"; icon="x" ;;
  *)     verdict=unknown; colour="#9f9f9f"; icon="grey_question" ;;
esac

label=${SONAR_SCOPE:-}; label=${label#*=}
if [[ ${SONAR_SCOPE:-} == pullRequest=* ]]; then
  dash="$host/summary/new_code?id=$project&pullRequest=$label"
  heading="PR #$label"
else
  dash="$host/project/overview?id=$project&branch=$label"
  heading="\`$label\`"
fi

# --- badge.svg: drawn here, no external request -----------------------
badge() {
  local txt=$1 msg=$2 fill=$3 out=$4 lw mw w
  lw=$(( ${#txt} * 7 + 12 )); mw=$(( ${#msg} * 7 + 12 )); w=$(( lw + mw ))
  cat > "$out" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="20" role="img" aria-label="$txt: $msg">
  <rect width="$w" height="20" rx="3" fill="#555"/>
  <rect x="$lw" width="$mw" height="20" rx="3" fill="$fill"/>
  <rect x="$lw" width="4" height="20" fill="$fill"/>
  <g fill="#fff" font-family="Verdana,DejaVu Sans,sans-serif" font-size="11" text-anchor="middle">
    <text x="$(( lw / 2 ))" y="14">$txt</text>
    <text x="$(( lw + mw / 2 ))" y="14">$msg</text>
  </g>
</svg>
SVG
}
badge "SonarQube" "$verdict" "$colour" "$report_dir/badge.svg"

# --- summary.md: committed, and written to the run summary -------------
{
  echo "## SonarQube Cloud — $heading"
  echo
  echo "**Quality Gate: :$icon: ${verdict^}** · [Open in SonarQube Cloud]($dash)"
  echo
  echo "| Metric | Value |"
  echo "| --- | --- |"
  echo "| Reliability | $(rating "$(m reliability_rating)") · $(m bugs) bug(s) |"
  echo "| Security | $(rating "$(m security_rating)") · $(m vulnerabilities) vulnerability(ies) |"
  echo "| Security hotspots | $(m security_hotspots) |"
  echo "| Maintainability | $(rating "$(m sqale_rating)") · $(m code_smells) smell(s) |"
  echo "| Coverage | $(m coverage)% |"
  echo "| Duplication | $(m duplicated_lines_density)% |"
  echo "| Lines of code | $(m ncloc) |"

  if [[ $(jq -r '[.projectStatus.conditions[]? | select(.status=="ERROR")] | length' "$report_dir/quality-gate.json") -gt 0 ]]; then
    echo
    echo "### Failing conditions"
    echo
    echo "| Metric | Comparator | Threshold | Actual |"
    echo "| --- | --- | --- | --- |"
    jq -r '.projectStatus.conditions[]? | select(.status=="ERROR")
           | "| \(.metricKey) | \(.comparator) | \(.errorThreshold) | \(.actualValue) |"' \
      "$report_dir/quality-gate.json"
  fi

  echo
  echo "_Analysis \`$analysis_id\` · refreshed $(date -u +%Y-%m-%dT%H:%M:%SZ)._"
} > "$report_dir/summary.md"

# Written to the run summary on every run, pass or fail, so the team reads the
# result straight from the run without opening .sast/report/sonarqube/summary.md.
[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$report_dir/summary.md" >> "$GITHUB_STEP_SUMMARY"
[[ -n ${GITHUB_OUTPUT:-} ]] && echo "gate=$verdict" >> "$GITHUB_OUTPUT"
[[ $verdict == unknown ]] && echo "::warning::could not determine the SonarQube Quality Gate status"

echo "sonar-report: gate=$verdict analysis=$analysis_id"

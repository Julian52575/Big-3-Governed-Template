#!/usr/bin/env bash
# Turn the SARIF that github/codeql-action/analyze just wrote into a small,
# branch-local record under .sast/report/codeql/ .
#
# Produces (ci-sast.yml's commit-reports job commits these to main on push):
#   results.sarif   raw CodeQL SARIF (all languages merged into one runs[])
#   findings.json   normalised finding list + counts by severity
#   summary.md      human-readable digest -- also written to the run summary
#   badge.svg       verdict badge, referenced by README.md via a relative path
#
# Inputs (env):
#   SARIF_DIR           dir holding the *.sarif from codeql-action/analyze (required)
#   CODEQL_SCOPE        "branch=<name>" or "pullRequest=<number>" -- heading only
#   GITHUB_SERVER_URL   https://github.com          (set by Actions)
#   GITHUB_REPOSITORY   "<owner>/<repo>"            (set by Actions)
#   GITHUB_RUN_ID       this run's id               (set by Actions)
#   GITHUB_REF_NAME     branch name fallback        (set by Actions)
#   GITHUB_STEP_SUMMARY optional; summary.md is appended to it when set
#   GITHUB_OUTPUT       optional; "gate=passed|warning|failed" written
#
# Gate: "failed" when any error-severity result is present, "warning" when only
# warning-severity results are present, otherwise "passed". ci-sast.yml fails
# the job on "failed" only -- a warning does not block, mirroring the SonarQube
# job's Quality Gate handling.
set -euo pipefail

sarif_dir=${SARIF_DIR:?SARIF_DIR is required}
report_dir=.sast/report/codeql
mkdir -p "$report_dir"

shopt -s nullglob
sarifs=("$sarif_dir"/*.sarif)
if (( ${#sarifs[@]} == 0 )); then
  echo "::error::no .sarif files in $sarif_dir -- did codeql-action/analyze run?"
  exit 1
fi

# --- merge every language's SARIF into one runs[] ----------------------
jq -s '{
  "$schema": (.[0]["$schema"] // "https://json.schemastore.org/sarif-2.1.0.json"),
  version:  (.[0].version // "2.1.0"),
  runs:     (map(.runs) | add)
}' "${sarifs[@]}" > "$report_dir/results.sarif"

# --- normalise results -----------------------------------------------
# Resolve each result's severity from result.level, else the rule's
# defaultConfiguration.level (CodeQL keeps query-pack rules under
# tool.extensions[].rules, plain rules under tool.driver.rules), else "warning".
findings=$report_dir/.findings.json
jq '
  [ .runs[]?
    | ( [ (.tool.driver.rules // [])[],
          (.tool.extensions // [])[]?.rules[]? ]
        | map({ key: .id,
                value: { level: (.defaultConfiguration.level // "warning"),
                         sev:   (.properties["security-severity"] // null),
                         name:  (.name // .shortDescription.text // .id) } })
        | from_entries ) as $rules
    | .results[]?
    | . as $r
    | ($r.ruleId // $r.rule.id // "unknown") as $rid
    | {
        ruleId:  $rid,
        name:    ($rules[$rid].name // $rid),
        level:   ($r.level // $rules[$rid].level // "warning"),
        securitySeverity: ($rules[$rid].sev),
        message: (($r.message.text // "") | gsub("[\r\n]+"; " ")),
        file:    ($r.locations[0].physicalLocation.artifactLocation.uri // ""),
        line:    ($r.locations[0].physicalLocation.region.startLine // null)
      }
  ]
' "$report_dir/results.sarif" > "$findings"

count() { jq --arg l "$1" '[.[] | select(.level == $l)] | length' "$findings"; }
errors=$(count error)
warnings=$(count warning)
notes=$(jq '[.[] | select(.level != "error" and .level != "warning")] | length' "$findings")
total=$(jq 'length' "$findings")

if   (( errors > 0 ));   then verdict=failed;  colour="#e05d44"; icon="x"
elif (( warnings > 0 )); then verdict=warning; colour="#dfb317"; icon="warning"
else                         verdict=passed;  colour="#4c1";    icon="white_check_mark"
fi

langs=$(jq -r '[.runs[]?.tool.driver.name] | map(select(. != null)) | unique | join(", ")' "$report_dir/results.sarif")

# --- findings.json: counts + the list -------------------------------
jq -n \
  --slurpfile f "$findings" \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg tool "${langs:-CodeQL}" \
  --arg verdict "$verdict" \
  --argjson errors "$errors" --argjson warnings "$warnings" \
  --argjson notes "$notes" --argjson total "$total" \
  '{ generatedAt: $generatedAt, tool: $tool, verdict: $verdict, total: $total,
     bySeverity: { error: $errors, warning: $warnings, note: $notes },
     findings: ($f[0] | sort_by(if .level=="error" then 0 elif .level=="warning" then 1 else 2 end)) }' \
  > "$report_dir/findings.json"
rm -f "$findings"

# --- badge.svg: drawn here, no external request --------------------
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
badge "CodeQL" "$verdict" "$colour" "$report_dir/badge.svg"

# --- summary.md: committed, and written to the run summary ----------
label=${CODEQL_SCOPE:-}; label=${label#*=}
if [[ ${CODEQL_SCOPE:-} == pullRequest=* ]]; then
  heading="PR #$label"
else
  heading="\`${label:-${GITHUB_REF_NAME:-workspace}}\`"
fi
if [[ -n ${GITHUB_REPOSITORY:-} && -n ${GITHUB_RUN_ID:-} ]]; then
  run_link=" · [Workflow run](${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID})"
else
  run_link=""
fi

{
  echo "## CodeQL — $heading"
  echo
  echo "**Result: :$icon: ${verdict^}** · ${total} alert(s)${run_link}"
  echo
  echo "| Severity | Count |"
  echo "| --- | --- |"
  echo "| Error | $errors |"
  echo "| Warning | $warnings |"
  echo "| Note | $notes |"

  if (( total > 0 )); then
    echo
    echo "### Findings"
    echo
    echo "| Severity | Rule | Location | Message |"
    echo "| --- | --- | --- | --- |"
    jq -r '
      def sev: if .level=="error" then "🔴 error"
               elif .level=="warning" then "🟡 warning"
               else "⚪ \(.level)" end;
      .findings[:50][]
      | "| \(sev) | `\(.ruleId)` | \(.file)\(if .line then ":" + (.line|tostring) else "" end) | \(.message) |"
    ' "$report_dir/findings.json"
    if (( total > 50 )); then
      echo
      echo "_… $(( total - 50 )) more — see \`.sast/report/codeql/findings.json\`._"
    fi
  fi

  echo
  echo "_Scanned ${langs:-CodeQL} · refreshed $(date -u +%Y-%m-%dT%H:%M:%SZ)._"
} > "$report_dir/summary.md"

# Written to the run summary on every run, pass or fail, so the team reads the
# result straight from the run without opening .sast/report/codeql/summary.md.
[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$report_dir/summary.md" >> "$GITHUB_STEP_SUMMARY"
[[ -n ${GITHUB_OUTPUT:-} ]] && echo "gate=$verdict" >> "$GITHUB_OUTPUT"

echo "codeql-report: verdict=$verdict errors=$errors warnings=$warnings notes=$notes total=$total"

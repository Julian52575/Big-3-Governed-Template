#!/usr/bin/env bash
# Apply this template's GitHub repository governance in one run.
#
# Idempotent-ish: re-running recreates the ruleset (old one is deleted first)
# and re-PATCHes settings to the same values.
#
# Requires: gh (GitHub CLI) authenticated as a repo admin -- `gh auth login`.
# The built-in Actions GITHUB_TOKEN cannot change these, so this is a one-time
# manual step for whoever owns the repo made from the template.
#
# Usage:
#   scripts/apply-governance.sh                # act on the repo of the current dir
#   scripts/apply-governance.sh owner/name     # act on an explicit repo
#
# What it sets:
#   - branch ruleset on the default branch, imported from .github/rulesets/main.json
#   - merge button: squash only, PR title as the commit subject
#   - auto-delete merged branches, always suggest updating PR branches, auto-merge
#   - Dependabot alerts + automated security fixes
#   - secret scanning + push protection      (public repo, or private with GHAS)
#   - private vulnerability reporting
#
# Security-scanning calls are best-effort: on a plan that does not include them
# the API returns an error, the script warns and continues.

set -euo pipefail

repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ruleset_file="$script_dir/../.github/rulesets/main.json"

echo "==> Target repo: $repo"
[ -f "$ruleset_file" ] || { echo "missing $ruleset_file" >&2; exit 1; }

# Best-effort wrapper: warn instead of aborting the whole script.
try() {
  if ! "$@"; then
    echo "    !! skipped (API rejected it -- plan/permissions?): $*" >&2
  fi
}

echo "==> Branch ruleset on the default branch"
# Delete an existing ruleset of the same name so this stays repeatable.
existing="$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name=="Auto Big-3-Governance main ruleset") | .id' 2>/dev/null || true)"
if [ -n "$existing" ]; then
  echo "    replacing existing ruleset id $existing"
  gh api --method DELETE "repos/$repo/rulesets/$existing" >/dev/null
fi
gh api --method POST "repos/$repo/rulesets" --input "$ruleset_file" >/dev/null
echo "    created ruleset 'Auto Big-3-Governance main ruleset'"

echo "==> Pull-request / merge settings"
gh api --method PATCH "repos/$repo" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=BLANK \
  -F delete_branch_on_merge=true \
  -F allow_update_branch=true \
  -F allow_auto_merge=true >/dev/null
echo "    squash-only; PR title becomes the commit subject"

echo "==> Dependabot alerts + automated security fixes"
try gh api --method PUT "repos/$repo/vulnerability-alerts"
try gh api --method PUT "repos/$repo/automated-security-fixes"

echo "==> Secret scanning + push protection"
try gh api --method PATCH "repos/$repo" \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'

echo "==> Private vulnerability reporting"
try gh api --method PUT "repos/$repo/private-vulnerability-reporting"

echo "==> Done. Review at: https://github.com/$repo/settings/rules"

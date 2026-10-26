# Template back-port plan: Zero-To-Kaban + serverless-pixelwar → Big-3-Secure-Template

> **Audience:** an AI agent implementing these changes on `Big-3-Secure-Template`.
> **Sources (sibling checkouts):** `../Zero-To-Kaban` (ZTK, last seen `153ca5d`), `../serverless-pixelwar` (SPW, branch `feat/serverless-deployment`, last seen `0b83a3c`).
> SPW items marked **(new)** appeared on that branch (vs `main@1057234`); line numbers refer to that branch.
> **Baseline:** this repo at `411742b` (`main`).
> Ignore `../Zero-To-Kaban/.claude/worktrees/**` — stale worktrees, not sources.

## Status: implemented on `feat/import-other-projects`

Every task T1–T14 is implemented, one commit per task. Deviations from the
plan, and issues found along the way:

- **T2:** the template's `ossf/scorecard-action` pin pointed at a SHA that does
  not exist upstream; re-pinned to the real v2.4.4 commit (separate `fix(ci)`
  commit).
- **T2b:** `pin-github-action` in SPW did have its hashes; copied as-is.
- **T3:** the new `sigstore/cosign-installer` SHA (`dc72c7d…`) is the correct
  v3.7.0 commit; SPW `main`'s old one was wrong.
- **T5:** the Code of Conduct is Contributor Covenant **2.0** (ZTK's copy),
  not 2.1; the enforcement contact is `[INSERT CONTACT METHOD]`.
- **T7:** implemented with osv-scanner 2.7.0 (container, pinned by digest)
  instead of `npm audit`.
- **T8:** the stack job exposed that `traefik:v3.3` cannot talk to Docker
  Engine 29 (client API 1.24); bumped to `v3.7` (separate `fix(compose)` commit).
- **T10:** `.sast/bin/*-report.sh` crashed under `set -u` without a `*_SCOPE`
  variable; fixed. SonarQube and report commits switch on by secret.
- **T11:** macOS uses host Podman (Podman Desktop/Homebrew); `podman` itself is
  Linux-only in the flake. The Darwin branch is evaluated and syntax-checked
  but was not run on a Mac.
- **T14:** both workflows are enabled with repository variables
  (`MAKE_PR_DRAFT`, `DISCORD_NOTIFY`).

## 0. Rules for the implementer

1. **One task = one branch = one PR**, Conventional Commit title (`ci: …`, `feat(devshell): …`, `docs: …`). Every PR needs a linked issue (the `linked-issue` check is required).
2. **Generify on copy.** The source repos hardcode project values. Replace every occurrence of:
   | Source literal | Replace with |
   | --- | --- |
   | `Julian52575/Zero-To-Kanban`, `Julian52575/serverless-pixelwar` | `OWNER/REPO` (same convention as `.github/ISSUE_TEMPLATE/config.yml`) |
   | `ghcr.io/julian52575/masterpoulet-serverless-pixelwar-…` | `ghcr.io/${{ github.repository }}-${{ matrix.image }}` (lower-cased) |
   | `backend` / `frontend` workspaces, `npm`, `node-version: 24` | this template's `api` / `web` dirs; language-specific steps go behind a clearly marked `# CUSTOMISE:` comment |
   | `package-name: zero-to-kanban` | `REPO` placeholder |
3. **Pin every action by full SHA + `# vX.Y.Z` comment.** Several source workflows use floating tags (`actions/github-script@v7`, `actions/checkout@v4`) — this would regress the OpenSSF *Pinned-Dependencies* score. Reuse the SHAs already pinned in this repo where the same action exists.
4. **Every new workflow:** top-level `permissions:` least-privilege, `timeout-minutes` on every job, `persist-credentials: false` on every checkout (a job that pushes passes its token through a step-scoped `env:` remote URL instead — see T10), `step-security/harden-runner` (`egress-policy: audit`) as each job's first step, and **no `${{ … }}` inside `run:`** — map it into `env:` and use `"$VAR"` (zizmor *template-injection*). SPW's new branch applies all of these; copy from it, not from `main`.
5. **Any new mandatory job** → add it to `ci-required.needs` in `.github/workflows/ci.yml`, never to `.github/rulesets/main.json` directly.
6. **Update `README.md`** (sections *Governance*, *Continuous integration*, *Layout*, *Just commands*) in the same PR as the feature it documents.
7. Comments: short, explain *why*. The sources are verbose — trim when copying.
8. Validate before PR: `nix flake check --no-build`, `just --list`, `actionlint`, `zizmor .github/workflows/` (all available in the dev shell once T2b lands; before that, use `nix shell nixpkgs#actionlint nixpkgs#zizmor`).

## 1. Gap matrix (what exists where)

Legend: ✅ present · ➕ added vs template · ✏️ modified vs template · — absent

| Area | Item | Template | ZTK | SPW | Verdict |
| --- | --- | --- | --- | --- | --- |
| CI | `ci.yml` `devshell` + `ci-required` | ✅ | ✅ | ✅ | keep |
| CI | `paths-ignore` on push | — | ➕ | ➕ | **import (P1)** |
| CI | `dockerfile-lint` (hadolint, auto-discovers) | — | — | ➕ | **import (P1)** |
| CI | `compose-lint` | — (inside devshell) | — | ➕ | **import (P1)** |
| CI | `workflow-lint` (actionlint + shellcheck) + `.github/actionlint.yaml` | — | ➕ | ➕ | **import (P1)** |
| CI | `zizmor` job (workflow security audit) **(new)** | — | — | ➕ | **import (P1)** |
| CI | `harden-runner` first step in every job **(new)** | — | — | ➕ | **import (P1)** |
| CI | `${{ }}` moved out of `run:` into `env:` (release workflows) **(new)** | n/a | — | ✏️ | apply rule 4 everywhere |
| CI | PR-title check: `pull_request_target` → `pull_request` **(new)** | `pull_request_target` | — | ✏️ | **import (P1)** |
| CI | `dependencies-audit` with gate + step summary | — | — | ➕ | **import as pattern (P2)** |
| CI | `stack` job (compose up + smoke); **(new)** no longer `needs` level-1 jobs | — | ➕ | ✏️ | **import skeleton (P2)** |
| CI | `ci-required`: anything but `success` fails **(new)** | — | — | ✏️ | **import (P1)** |
| CI | `ci-sast.yml` (SonarQube + CodeQL, guard, reports committed to `.sast/report`) | — | ➕ | ➕ | **import, opt-in (P2)** |
| CI | `check-pr-linked-issue`: skip `release-please-*` branches | ✅ | ✏️ | — | **import (P1)** |
| CI | `check-conventional-commit-pr-title`: concurrency group incl. `event_name` | ✅ | — | ✏️ | **import (P1)** |
| CI | `make-pr-draft.yml` | — | ➕ | — | optional (P3) |
| CI | `notify-discord-review-requested.yml` | — | — | ➕ | optional (P3), disabled by default |
| CI | `frontend-and-auth-accessibility.yml` (RGAA), `jira-issues-sync.yml`, `bump-helm-chart.yml` | — | ➕ | — | **skip** (project-specific) |
| CI | GitNexus job + `.github/scripts/gitnexus.sh` | — | ➕ | ➕ | skip (tool-specific); mention in README as extension |
| CD | `release-please.yml` + config + manifest | — | ➕ | ➕ | **import (P1)** |
| CD | `release-to-ghcr.yml` (buildx, SBOM, cosign keyless) | — | ➕ | ✏️ | **import (P1)** |
| Hooks | `check-signature` (sign-off + signing config) | — | — | ➕ | **import, opt-in (P2)** |
| Dev env | flake: `x86_64-darwin` + macOS Podman-machine branch | — | ✏️ | ✏️ | **import after cleanup (P2)** |
| Dev env | shellHook: create `.env` from `.env.example` | — | ✏️ | ✏️ | **import (P1)** |
| Dev env | shellHook: generate secrets matching `change-me-*` | — | ✏️ | — | **import, generic (P2)** |
| Dev env | Workflow-lint tools in devshell: `actionlint`, `shellcheck`, `check-jsonschema`, `zizmor`, `pin-github-action` **(new)** | — | — | ➕ | **import (P1)** |
| Dev env | `nix/tools.nix` pinned upstream binaries (now also `zizmor` matching CI version) | — | — | ✏️ | **import as pattern (P2)** |
| Dev env | justfile: top-level vars, `positional-arguments`, `project` | — | ✏️ | ✏️ | **import (P1)** |
| Dev env | justfile: `nuke` does volume prune + backup-before-nuke | — | ✏️ | ✏️ | **import (P2)** |
| Dev env | justfile: `database-dump` / `database-pipe` | — | ➕ | ➕ | import, commented-out Postgres example (P3) |
| Collab | ADR Discussion template + `adr-discussion-sync.yml` + `docs/adr/` | — | ➕ | SPW: template only | **import (P2)** |
| Collab | Issue forms: optional “ADR discussion” field + footer | — | ✏️ | ✏️ | import with ADR feature (P2) |
| Collab | `config.yml`: “Question / help” → Discussions enabled | commented | — | ✏️ | import with ADR feature (P2) |
| Collab | `CONTRIBUTING.md` (governance chain, labels, PR gate, releasing) | — | ➕ | ➕ (`CONTRIBUTOR.md`) | **import (P1)** — name it `CONTRIBUTING.md` |
| Collab | `CODE_OF_CONDUCT.md` (Contributor Covenant) | — | ➕ | — | **import (P1)** |
| Collab | `docs/Troubleshoot.md` incident log (error/cause/solution, no duplicates) + rules in CONTRIBUTOR **(new)** | — | — | ➕ | **import (P1)** |
| Collab | CONTRIBUTOR “Local testing tools” table **(new)** | — | — | ➕ | **import into CONTRIBUTING (P1)** |
| Collab | `AGENTS.md` + `CLAUDE.md` → “See AGENTS.md” | — | — | ➕ | **import, without GitNexus block (P2)** |
| Collab | `CHANGELOG.md` | — | ➕ | ➕ | generated by release-please — don't hand-create |
| Collab | GDPR docs (`docs/grpd/`) | — | ➕ | — | skip (domain-specific) |
| Security | OpenSSF weekly cron disabled in ZTK | ✅ cron | ✏️ off | — | **do not import** (template should keep it on) |
| Ruleset | SPW removed `linked-issue` from required checks | ✅ | — | ✏️ | **do not import** |

## 2. Tasks (ordered; each is self-contained)

Each task: **Goal · Source · Target · Steps · Acceptance**.

---

### T1 — CI hygiene: `paths-ignore`, concurrency fix, release-please skip  `P1`

- **Source:** `../serverless-pixelwar/.github/workflows/ci.yml` (lines 4–11), `../serverless-pixelwar/.github/workflows/check-conventional-commit-pr-title.yml` (concurrency), `../Zero-To-Kaban/.github/workflows/check-pr-linked-issue.yml` (script head).
- **Target:** `.github/workflows/ci.yml`, `check-conventional-commit-pr-title.yml`, `check-pr-linked-issue.yml`.
- **Steps:**
  1. Add to `ci.yml` `on.push`:
     ```yaml
     paths-ignore:
       - "*.md"
       - ".gitignore"
       - ".github/ISSUE_TEMPLATE/**"
       - ".github/rulesets/**"
       - ".sast/report/**"
     ```
     Only on `push`, **never** on `pull_request` (required checks would hang as “expected”).
  2. PR-title concurrency group → `${{ github.workflow }}-${{ github.event_name }}-${{ github.event.pull_request.number || github.ref }}` (prevents `edited` runs cancelling `opened` runs).
  2b. PR-title trigger: `pull_request_target` → `pull_request` (SPW new branch). It needs no secrets, and `pull_request_target` is flagged by zizmor (*dangerous-triggers*). Update the workflow's header comment to match `check-pr-linked-issue.yml`'s explanation.
  3. In `check-pr-linked-issue.yml` script, before the GraphQL query, early-return when `context.payload.pull_request.head.ref.startsWith('release-please-')`.
  4. **Do not** add `synchronize` to its `types` (ZTK did; the template's comment explains why it's unnecessary).
- **Acceptance:** actionlint clean; a docs-only push to `main` triggers no `ci` run.

### T2 — Generic lint jobs  `P1`

- **Source:** `../serverless-pixelwar/.github/workflows/ci.yml` jobs `dockerfile-lint`, `compose-lint`, `workflow-lint`; `../serverless-pixelwar/.github/actionlint.yaml`.
- **Target:** `.github/workflows/ci.yml`, `.github/actionlint.yaml`.
- **Steps:**
  1. Copy the three jobs verbatim (they are already project-agnostic; hadolint uses `git ls-files` discovery).
  2. Images are tag-pinned (`hadolint:v2.12.0`, `actionlint:1.7.12`); upgrade to `@sha256:` digests for Scorecard.
  3. Copy `actionlint.yaml` only if T9 (ADR sync) is implemented — its sole ignore rule is for that workflow.
  4. Add the `zizmor` job (SPW `ci.yml` ~line 550): `pipx run zizmor==1.31.1 --format github .` with `GH_TOKEN: ${{ github.token }}` for online audits. Fix every finding in existing template workflows in the same PR (expect: `pull_request_target`, `${{ }}` in `run:`).
  5. Add `harden-runner` (pinned SHA from SPW: `dc2769abcc0fcfbadfc1df54081c1608579ef6b2 # v2.22.2`, `egress-policy: audit`) as the first step of **every** job in every template workflow, including `ci-required`.
  6. Replace `ci-required`'s check with SPW's stricter one — anything but `success` fails:
     ```bash
     if printf '%s\n' '${{ join(needs.*.result, ' ') }}' | tr ' ' '\n' | grep -vqx 'success'; then
     ```
  7. Add the four lint jobs to `ci-required.needs`.
  8. Template ships `api/Dockerfile` and `web/Dockerfile` — fix any hadolint findings in them in the same PR.
- **Acceptance:** all four jobs green on the template as-is; zizmor reports zero findings.

### T2b — Local workflow tooling in the dev shell  `P1`

- **Source:** `../serverless-pixelwar/flake.nix` (`check-jsonschema`, `actionlint`, `shellcheck`), `../serverless-pixelwar/nix/tools.nix` (`zizmor`, `pin-github-action`), CONTRIBUTOR “Local testing tools” table.
- **Target:** `flake.nix`, `nix/tools.nix`.
- **Steps:**
  1. Add `actionlint`, `shellcheck`, `check-jsonschema` from nixpkgs.
  2. Create `nix/tools.nix` with only `zizmor` (pinned to the **same version as CI** — nixpkgs lags) and `pin-github-action`; import its `.all` in the shell. Leave out SPW's terraform/helm/kubectl/gcloud (project-specific).
  3. `pin-github-action` in SPW has no `hash`/`npmDepsHash` in the diff — verify it builds; add the hashes.
  4. Add `just lint-workflows` → `actionlint && zizmor .github/workflows/ && check-jsonschema --builtin-schema vendor.github-workflows .github/workflows/*.yml`.
- **Acceptance:** `nix develop -c just lint-workflows` passes; CI zizmor version == `tools.nix` version.

### T3 — Release automation (release-please + GHCR)  `P1`

- **Source:** `../serverless-pixelwar/.github/workflows/release-please.yml`, `release-to-ghcr.yml`, `release-please-config.json`, `.release-please-manifest.json`; changelog sections from `../Zero-To-Kaban/release-please-config.json`.
- **Target:** same paths at repo root / `.github/workflows/`.
- **Steps:**
  1. `release-please-config.json`: use ZTK's `changelog-sections` + SPW's `pull-request-title-pattern`. `release-type: "simple"` (template has no language; note `# CUSTOMISE` in README). `package-name: "REPO"`.
  2. `.release-please-manifest.json`: `{ ".": "0.0.0" }`.
  3. `release-please.yml`: replace the Node-specific `paths:` filter with no filter (or `paths-ignore` like T1) — keep `.release-please-manifest.json` triggering. Fix the stale comment: it says the built-in token suffices but uses `secrets.RELEASE_PLEASE_GITHUB_TOKEN`; document that a PAT/App token is **required** so the release event triggers `release-to-ghcr`.
  4. `release-to-ghcr.yml` (copy from SPW's new branch — it already moves `IMAGE`/`DIGEST` into `env:`): matrix → `api` / `web`; image name from `github.repository` lower-cased (use a step: `echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY,,}-${{ matrix.image }}" >> "$GITHUB_ENV"`). Checkout with default token + `persist-credentials: false` (SPW's `RO_TOKEN` is project-specific). Add top-level `permissions: {}`, job-level `contents: read, packages: write, id-token: write`. Keep `sbom: true` + cosign keyless signing; consider adding `provenance: mode=max`. **Verify the `sigstore/cosign-installer` SHA:** SPW changed it to `dc72c7d…` but kept the comment `# v3.7.0` — resolve the tag and fix SHA or comment.
  5. README: new *Releasing* section listing required secrets.
- **Acceptance:** actionlint clean; `workflow_dispatch` with tag `manual-test` pushes signed images (verify with `cosign verify`).

### T4 — Dev shell: `.env` bootstrap and justfile refactor  `P1`

- **Source:** shellHook head in `../serverless-pixelwar/flake.nix`; justfile header + `nuke` in `../Zero-To-Kaban/justfile`.
- **Target:** `flake.nix`, `justfile`.
- **Steps:**
  1. shellHook: before the `.env` load, `cp .env.example .env` when `.env` is missing.
  2. justfile: move `tool`/`compose` to the top; add `set positional-arguments := true` and `project := lowercase(file_name(justfile_directory()))`.
  3. `nuke`: after `just rm`, `{{tool}} volume prune --force --filter "label=com.docker.compose.project={{project}}"`. Keep the backup hook as an optional `just _pre-nuke` recipe (no-op by default) rather than hard-wiring `database-dump`.
- **Acceptance:** fresh clone → `nix develop` creates `.env`; `just nuke` removes project volumes only.

### T5 — Collaboration docs: CONTRIBUTING + Code of Conduct  `P1`

- **Source:** `../Zero-To-Kaban/CONTRIBUTING.md` (structure), `../serverless-pixelwar/CONTRIBUTOR.md` (Setup, Commit hooks, SAST gates, coverage policy), `../Zero-To-Kaban/CODE_OF_CONDUCT.md`.
- **Target:** `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`.
- **Steps:**
  1. Outline: Setup → Governance chain (ADR → Issue → Branch → PR) → Issues & labels → Branching & commits → PR gate (list each required check and what fixes it) → Releasing → Related automation.
  2. Strip project-specific bits (RGAA, Jira, Helm, Kanban domain). Sections depending on optional features (ADR, SAST, signing) get a one-line “if enabled” note.
  3. CoC: Contributor Covenant 2.1 verbatim, enforcement contact = `OWNER` placeholder.
  4. Move the governance prose currently in `README.md` §Governance into CONTRIBUTING; README keeps a summary + link.
  5. Add a *Local testing tools* table (SPW CONTRIBUTOR.md, new branch) listing only the tools the template's shell provides after T2b.
  6. Add a *Troubleshooting* section with SPW's rules (each entry: **Error**, **Occurrences**, **Cause**, **Solution**; no duplicates — add an occurrence to the existing entry; cross-link entries) and create `docs/Troubleshoot.md` with a header and one commented example entry.
- **Acceptance:** GitHub *Community Standards* page shows both files detected; `docs/Troubleshoot.md` exists.

### T6 — Commit signing hook (opt-in)  `P2`

- **Source:** `../serverless-pixelwar/.githooks/check-signature`, `.githooks/commit-msg`.
- **Target:** `.githooks/check-signature`, `.githooks/commit-msg`.
- **Steps:**
  1. Copy `check-signature`; gate it behind `git config --get hooks.requireSignature` = `true` (or an env var) so the template stays frictionless by default.
  2. `commit-msg`: run both checks (`check-conventional-commit-msg "$@" && check-signature "$@"`).
  3. Pair it with the ruleset: document enabling `required_signatures` in `.github/rulesets/main.json` (don't enable by default).
- **Acceptance:** with the flag unset, behaviour unchanged; with it set, unsigned config is rejected with the help text.

### T7 — Dependency audit job (pattern)  `P2`

- **Source:** `dependencies-audit` in `../serverless-pixelwar/.github/workflows/ci.yml`.
- **Target:** `.github/workflows/ci.yml`.
- **Steps:** keep the reusable shape — matrix per workspace, retry loop, “unknown posture fails”, severity table in `$GITHUB_STEP_SUMMARY`, raw artifact upload, gate (0 Critical/High, <5 Moderate+Low). The template has no package manager, so ship it as a commented-out job with `# CUSTOMISE:` marking the `npm audit` line; alternatively use a language-agnostic scanner (`osv-scanner` / `trivy fs`) so it can be enabled now. **Recommended:** `osv-scanner` — works on any lockfile.
- **Acceptance:** enabled job passes on the template (no lockfiles → exits 0 with a summary line).

### T8 — Level-2 `stack` job  `P2`

- **Source:** `stack` job in `../serverless-pixelwar/.github/workflows/ci.yml` (line ~331) and ZTK's `database` job.
- **Target:** `.github/workflows/ci.yml`.
- **Steps:**
  1. `cp .env.example .env`, `docker compose up -d --wait`, curl each published service, dump `compose logs` on failure, `down --volumes` always. `timeout-minutes: 10`.
  2. **No `needs:`** — SPW's new branch dropped the level-1 → level-2 DAG so `stack` runs in parallel (faster feedback; `ci-required` still gates everything). Follow that; don't add *Level* banners.
  3. Add to `ci-required.needs`.
- **Acceptance:** stack comes up healthy on the template's `api`/`web` services in CI.

### T9 — ADR workflow via GitHub Discussions  `P2`

- **Source:** `../serverless-pixelwar/.github/DISCUSSION_TEMPLATE/architecture-decision-records.yml`, `../Zero-To-Kaban/.github/workflows/adr-discussion-sync.yml`, issue-form diffs (both repos), `config.yml` diff (SPW).
- **Target:** `.github/DISCUSSION_TEMPLATE/architecture-decision-records.yml`, `.github/workflows/adr-discussion-sync.yml`, `docs/adr/.gitkeep`, `.github/ISSUE_TEMPLATE/*.yml`.
- **Steps:**
  1. Copy discussion template (drop the MySQL/Postgres placeholders for neutral ones).
  2. Copy sync workflow; **pin** `actions/checkout` and `actions/github-script` by SHA; keep `ADR_SYNC_GITHUB_TOKEN || GITHUB_TOKEN` fallback. Note: pushing to a protected `main` needs the PAT.
  3. Add the optional “ADR discussion” input + footer note to all four issue forms, with `OWNER/REPO` URLs.
  4. Uncomment the “Question / help” contact link in `config.yml`.
  5. Copy `.github/actionlint.yaml` (T2 step 3).
  6. Document: “Enable Discussions and create category *Architecture Decision Records*” in README setup steps.
- **Acceptance:** closing an Accepted test discussion commits `docs/adr/<title>-#<n>.md`; missing branch reopens it with the hint comment.

### T10 — SAST pipeline (opt-in)  `P2`

- **Source:** `../serverless-pixelwar/.github/workflows/ci-sast.yml`, `../serverless-pixelwar/.sast/**` (`bin/*.sh`, `codeql-config.yml`, `sonar-project.properties`), `../Zero-To-Kaban/.sast/README.md`.
- **Target:** same paths.
- **Steps:**
  1. Copy the guard → tools → `commit-reports` → `ci-sast-required` structure unchanged.
  2. Remove the Node coverage steps from the `sonarqube` job; leave a `# CUSTOMISE: generate coverage here` marker.
  3. CodeQL `languages:` → placeholder with a comment; default to `actions` (always valid: the repo has workflows).
  4. Make SonarQube skip cleanly when `SONARQUBE_TOKEN` is absent (extend guard), so the template works without a Sonar account.
  5. Add `ci-sast-required` to the ruleset only when enabled — document, don't default.
  6. Use SPW's new-branch `commit-reports`: checkout with `persist-credentials: false`, and push via a step-scoped `SAST_REPORT_TOKEN` env in `https://x-access-token:${SAST_REPORT_TOKEN}@github.com/${GITHUB_REPOSITORY}.git` — the PAT never lands in `.git/config`.
- **Acceptance:** with no secrets set, `ci-sast` is green (CodeQL runs, Sonar no-ops with a logged reason).

### T11 — macOS dev shell support  `P2`

- **Source:** shellHook `Darwin` branch in `../Zero-To-Kaban/flake.nix` / `../serverless-pixelwar/flake.nix`.
- **Target:** `flake.nix`.
- **Steps:**
  1. Add `x86_64-darwin` **and** `aarch64-darwin` to `systems`.
  2. Port the Darwin branch with fixes required before import:
     - Never `exit 1` in a shellHook (kills the user's shell / `direnv`); `echo … >&2` and `return`.
     - Don't hardcode `/tmp/podman-tmp/podman/podman-machine-default-api.sock`; derive it from `podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}'`.
     - Remove French comments; drop the dead `[ -z "$podman_sock" ]` check.
     - Linux-only packages (`catatonit`, `util-linux`, rootless helpers) behind `lib.optionals pkgs.stdenv.isLinux`.
  3. Keep the existing Linux branch (in-repo podman config, network-fs detection) untouched.
  4. CI: `nix flake check --no-build --all-systems` in `devshell` job.
- **Acceptance:** `nix flake check --all-systems --no-build` passes; Linux behaviour unchanged.

### T12 — Secret seeding in shellHook (generic)  `P2`

- **Source:** `SESSION_SECRET` block in `../Zero-To-Kaban/flake.nix`.
- **Target:** `flake.nix`, `.env.example`.
- **Steps:** generalise — for every `KEY=change-me-*` line in `.env`, replace the value with `openssl rand -hex 32`. Add `openssl` to the shell. Document the `change-me-` convention in `.env.example`.
- **Acceptance:** fresh `nix develop` leaves no `change-me-` values in `.env`; re-entering does not rotate them.

### T13 — AI agent instructions  `P2`

- **Source:** `../serverless-pixelwar/AGENTS.md`, `CLAUDE.md`.
- **Target:** `AGENTS.md`, `CLAUDE.md`.
- **Steps:** `AGENTS.md` = pointer to README/CONTRIBUTING + the hard rules (Conventional Commits, linked issue, pinned actions, least-privilege permissions, add jobs via `ci-required`). `CLAUDE.md` = `See AGENTS.md`. **Exclude** the GitNexus block and `.claude/skills/gitnexus-*` (tool-specific, auto-generated).
- **Acceptance:** both files exist; no tool-specific content.

### T14 — Optional workflows  `P3`

Ship each disabled (trigger = `workflow_dispatch` only, or guarded by a repo variable) and documented under README *Optional automation*:

| File | Source | Notes before import |
| --- | --- | --- |
| `make-pr-draft.yml` | ZTK | pin `github-script` by SHA; drop `contents: write` (only `pull-requests: write` needed); skip `release-please-*` heads |
| `notify-discord-review-requested.yml` | SPW | guard with `if: vars.DISCORD_NOTIFY == 'true'` and secret presence; already pinned + harden-runner |
| `database-dump` / `database-pipe` just recipes | ZTK/SPW | ship commented as a Postgres example; dedupe the shared “start db if down” block into one `_ensure-db` recipe |

## 3. Explicitly NOT imported

| Item | Reason |
| --- | --- |
| ZTK disabling the OpenSSF cron | Template should keep weekly Scorecard |
| SPW removing `linked-issue` from ruleset | Weakens the governance chain the template promotes |
| ZTK adding `synchronize` to linked-issue trigger | Wasted runs; template comment already explains |
| RGAA a11y, Jira sync, Helm bump, GDPR docs, Argo/K8s deployment flake | Domain/project-specific |
| SPW `just reset` | References `Puniemu.csproj`, project-specific |
| GitNexus CI job, scripts, `docs/gitnexus/`, `.claude/skills/` | Tool-specific; at most a README “extensions” mention |
| `tmp/`, `api-scripts/`, `CHANGELOG.md` content | Project artifacts |
| All Terraform / IaC: `terraform-{deploy,destroy}.yml`, CI `terraform` job, `infra/`, terraform/helm/kubectl/gcloud in `nix/tools.nix` | Out of scope for this template |
| SPW `docs/Troubleshoot.md` entries | Project incidents; only the format is imported (T5) |

## 4. Suggested PR order

`T1 → T2b → T2 → T4 → T5 → T3 → T13 → T6 → T7 → T8 → T9 → T12 → T11 → T10 → T14`

Rationale: cheap hygiene first; local lint tooling, then CI lint + zizmor + hardening before anything adds new workflows (so they guard later PRs); docs before automation that the docs describe; opt-in/heavy features last.

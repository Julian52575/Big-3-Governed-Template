# `.sast/` — Static Application Security Testing

Config, helper scripts and branch-local reports for the jobs in
[`.github/workflows/ci-sast.yml`](../.github/workflows/ci-sast.yml).

**Opt-in by secret.** With no secrets set, only CodeQL runs (on the
workflows, language `actions`) and reports stay in the run summary.
`SONARQUBE_TOKEN` switches SonarQube on; `SAST_REPORT_TOKEN` switches on the
report commits to `main`. To make SAST block merges, add `ci-sast-required`
to `required_status_checks` in `.github/rulesets/main.json`.

```
.sast/
├── sonar-project.properties   SonarQube Cloud scan settings
├── codeql-config.yml          CodeQL paths / query suite
├── bin/
│   ├── sonar-report.sh        builds report/sonarqube/ from a finished analysis
│   └── codeql-report.sh       builds report/codeql/ from the analyze SARIF
└── report/
    ├── sonarqube/             refreshed by CI on push to main
    │   ├── summary.md         human-readable digest (also written to the run summary, pass or fail)
    │   ├── badge.svg          gate badge, shown in the root README
    │   ├── measures.json      raw metric values
    │   └── quality-gate.json  raw gate status + failing conditions
    └── codeql/                refreshed by CI on push to main
        ├── summary.md         human-readable digest (also written to the run summary, pass or fail)
        ├── badge.svg          verdict badge, shown in the root README
        ├── findings.json      normalised findings + counts by severity
        └── results.sarif      raw CodeQL SARIF (all languages merged)
```

## How the report stays current

On every **pull request** each tool's job in `ci-sast.yml` runs its scan, builds
`report/<tool>/`, writes that digest to the **run summary** (pass or fail, so
the team can read the result without opening the report files), and enforces
that tool's gate — but commits nothing.

On **push to `main`** (i.e. after a PR merges) the same scan runs, and a single
`commit-reports` job then collects every tool's report and commits them to
`main` in **one commit** whose message ends with `[skip ci]`. So the committed
files — and the README badge, which references `badge.svg` by a **relative
path** — track the latest `main`, and PR branches never carry report commits
(hence never hit report merge conflicts).

The commit is pushed with the **`SAST_REPORT_TOKEN`** PAT (Contents: read and
write), passed only to the push step and never stored in `.git/config`, so a protected `main` accepts it without a GitHub Actions ruleset
bypass. A PAT push would normally re-trigger `ci` / `ci-sast`; the `[skip ci]`
marker in the commit message plus a `.sast/report/**` `paths-ignore` on both
workflows stop that — no self-trigger loop. `cancel-in-progress` is `false` for
push, so the commit also cannot cancel an in-flight run.

**Skipped runs:** draft pull requests (SAST runs once the PR is marked ready)
and pull requests from forks (no `SONARQUBE_TOKEN`) — the tool jobs run to green
as a no-op, `commit-reports` is skipped, and `ci-sast-required` stays green.

## SonarQube Cloud

One-time setup:

1. Sign in at <https://sonarcloud.io> with the GitHub account and create an
   organization bound to this repo's owner.
2. **Analysis Method:** in the project's
   *Administration → Analysis Method*, turn **Automatic Analysis off**. It
   conflicts with the CI-based scan and the workflow will error while it's on.
3. Generate a token (*My Account → Security*) and add it to the repo as the
   `SONARQUBE_TOKEN` Actions secret.
4. Put the org key and project key into `sonar-project.properties` (the
   `REPLACE_WITH_*` placeholders).
5. Add a **`SAST_REPORT_TOKEN`** Actions secret — a PAT with *Contents: read
   and write* on this repo — so `commit-reports` can push the `[skip ci]`
   report commit to `main`. If a ruleset protects `main`, add that PAT's
   account to its bypass list.
6. Let one run land on `main` first — SonarQube Cloud needs a base-branch
   analysis before it can decorate pull requests.

The full analysis (issues, hotspots, history) stays in the SonarQube Cloud UI;
`report/sonarqube/` is just the at-a-glance record. The job fails if the
project's **Quality Gate** does not pass.

## CodeQL

Runs entirely inside the workflow — `github/codeql-action/init` +
`analyze` with **`build-mode: none`** and
**`upload: never`**, so it depends on neither GitHub Advanced Security nor code
scanning being enabled and the `codeql` job needs only `contents: read`.

`bin/codeql-report.sh` parses the SARIF `analyze` writes to
`.sast/codeql-results/` (git-ignored scratch) into `report/codeql/`:

- **`findings.json`** — every result normalised to
  `{ ruleId, name, level, securitySeverity, message, file, line }`, plus
  `bySeverity` counts and a `verdict`.
- **`summary.md`** — the digest, also written to the run summary (pass or fail).
- **`badge.svg`** — `passed` (green) / `warning` (yellow) / `failed` (red),
  referenced by `README.md` via a relative path.
- **`results.sarif`** — the raw SARIF, kept so it can be uploaded later by hand.

**Gate:** the job fails when any **error-severity** result is present (CodeQL
marks high/critical security issues as `error`). Warning- and note-severity
results are recorded but do not block, mirroring the SonarQube job.

**Languages** are set in `ci-sast.yml` (`languages:`, marked `CUSTOMISE`).
The template ships `actions` only — it always has workflows to scan. Add
your languages; compiled ones may need a different `build-mode`.

What to scan and which query suite live in
[`codeql-config.yml`](./codeql-config.yml) — `paths` mirrors
`sonar-project.properties`' `sonar.sources`.

To also publish findings to the repo's **Security → Code scanning** tab, set
`upload: always` on the `Analyze` step and add `security-events: write` to the
`codeql` job's `permissions`. If GitHub's **default setup** for code scanning is
enabled it must be turned off first (*Settings → Code security → Code scanning →
Set up → Advanced*), the same way SonarQube Cloud's Automatic Analysis has to be
off — an advanced workflow and default setup cannot both run.

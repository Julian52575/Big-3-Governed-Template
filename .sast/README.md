# `.sast/` — Static Application Security Testing

Config, report scripts and committed reports for
[`ci-sast.yml`](../.github/workflows/ci-sast.yml).

| Secret | Turns on |
| ------ | -------- |
| *(none)* | CodeQL on every ready PR and push to `main`; results in the run summary |
| `SONARQUBE_TOKEN` | SonarQube Cloud scan + Quality Gate |
| `SAST_REPORT_TOKEN` | committing reports to `.sast/report/` on each push to `main` |

Drafts and fork PRs are skipped and stay green. To make SAST block merges, add
`ci-sast-required` to `required_status_checks` in `.github/rulesets/main.json`.

```
sonar-project.properties   SonarQube settings
codeql-config.yml          CodeQL paths / query suite
bin/*-report.sh            turn each tool's output into report/<tool>/
report/<tool>/             summary.md, badge.svg (embeddable), raw JSON/SARIF
```

## How reports are committed

PRs only write the digest to the run summary. On push to `main`, the
`commit-reports` job commits every tool's report in one `[skip ci]` commit,
pushed with `SAST_REPORT_TOKEN` (fine-grained PAT, *Contents: read and write*).
`[skip ci]` and a `.sast/report/**` `paths-ignore` prevent a re-trigger loop.
If a ruleset protects `main`, give the PAT's account a bypass — and note these
commits are unsigned.

## CodeQL

Runs with `build-mode: none` and `upload: never`, so it needs neither GitHub
Advanced Security nor code scanning. The job fails on any **error**-severity
result; warnings and notes are only reported.

- **Languages:** `languages:` in `ci-sast.yml` (ships with `actions`). Compiled
  languages may need another
  [build mode](https://docs.github.com/en/code-security/code-scanning/creating-an-advanced-setup-for-code-scanning/codeql-code-scanning-for-compiled-languages).
- **Paths and query suite:** [`codeql-config.yml`](codeql-config.yml)
  ([reference](https://docs.github.com/en/code-security/code-scanning/creating-an-advanced-setup-for-code-scanning/customizing-your-advanced-setup-for-code-scanning)).
- **Security tab:** set `upload: always` and grant `security-events: write`;
  turn off GitHub's code-scanning *default setup* first.

## SonarQube Cloud

1. Create an organisation and project at <https://sonarcloud.io>, and turn
   **Automatic Analysis off** (it conflicts with the CI scan).
2. Add the analysis token as the `SONARQUBE_TOKEN` secret.
3. Fill in the `REPLACE_WITH_*` keys in `sonar-project.properties`.
4. Let one run land on `main` before expecting PR analysis.

The job fails when the Quality Gate fails. Coverage must be generated in the
job (`CUSTOMISE` marker) — SonarQube only imports reports. Parameters:
[analysis parameters](https://docs.sonarsource.com/sonarqube-cloud/advanced-setup/analysis-parameters/).

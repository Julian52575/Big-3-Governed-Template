# Adapting this template

Everything to do after **Use this template** so the dev shell, CI, releases
and governance work in your repository. Work top to bottom; each step says
what breaks if you skip it. Steps marked *(optional)* switch on extra features.

## 1. Local setup (every contributor)

1. Install Nix with flakes ([Determinate installer](https://install.determinate.systems/))
   and, on Linux, `uidmap` for rootless Podman. On macOS, install Podman
   Desktop (or `brew install podman`) and start a machine
   (`podman machine init && podman machine start`).
2. `nix develop` (or `direnv allow`). This creates `.env`, generates every
   `change-me-*` secret, and enables the git hooks.
3. Set up **commit signing**. The `commit-msg` hook rejects unsigned or
   un-signed-off commits:
   ```bash
   git config --global gpg.format ssh
   git config --global user.signingkey ~/.ssh/id_ed25519.pub
   git config --global commit.gpgsign true
   ```
   Add the key on GitHub as a **Signing Key**, and commit with `git commit -s`.
   If your project does not want signing, run
   `git config hooks.requireSignature false` in each clone.
4. `just up -d` and open <http://localhost:8000>.

## 2. Replace placeholders

| File | Replace | If you skip it |
| ---- | ------- | -------------- |
| `README.md` (top) | `Julian52575/Big-3-Governed-Template` in the badge URL; the title, intro, *Customising* section and © line | badge shows the template's score |
| `.github/ISSUE_TEMPLATE/config.yml` | `OWNER/REPO` in the security-advisory link | vulnerability reports go to the wrong repo |
| `CODE_OF_CONDUCT.md` | `[INSERT CONTACT METHOD]` | nobody to report conduct issues to |
| `release-please-config.json` | `"package-name": "REPO"`; `"release-type": "simple"` → your language (`node`, `python`, `rust`, …) so version files are bumped | releases work, but no package version file is updated |
| `.release-please-manifest.json` | your current version, if not `0.0.0` | the first release is computed from `0.0.0` |
| `.readme-badges/`, `SCORECARD.md` | delete; the Scorecard workflow regenerates them | the template's old results are shown |

## 3. Repository settings

With [`gh`](https://cli.github.com/) authenticated as a repo admin:

```bash
scripts/apply-governance.sh owner/name
```

It sets the branch ruleset (from `.github/rulesets/main.json`), squash-only
merges, read-only default `GITHUB_TOKEN`, Dependabot, secret scanning and
private vulnerability reporting, and creates the issue labels. Without it,
`main` is unprotected and none of the required checks block a merge.

Then, by hand:

- **Organisation** *(if any)*: require 2FA; *Actions → General* → require
  approval for fork pull request workflows.
- **CODEOWNERS** *(optional)*: add `.github/CODEOWNERS`; the ruleset already
  requires code-owner review once it exists.
- **Signed commits on GitHub** *(optional)*: add `{ "type": "required_signatures" }`
  to `rules` in `.github/rulesets/main.json` and re-run the script. Leave
  `SAST_REPORT_TOKEN` unset (or give its account a bypass) — its report
  commits are not signed.
- **SAST as a merge gate** *(optional)*: add `{ "context": "ci-sast-required" }`
  to `required_status_checks` in the same file and re-run the script.

## 4. Secrets

*Settings → Secrets and variables → Actions → Secrets.*

| Secret | Needed for | Scope | If unset |
| ------ | ---------- | ----- | -------- |
| `RELEASE_PLEASE_GITHUB_TOKEN` | `release-please.yml` | fine-grained PAT or GitHub App token on this repo: *Contents* and *Pull requests* read/write | release-please fails; with the built-in token instead, releases would not trigger `release-to-ghcr.yml` |
| `SONARQUBE_TOKEN` *(optional)* | `ci-sast.yml` SonarQube job | SonarQube Cloud analysis token | SonarQube is skipped; CodeQL still runs |
| `SAST_REPORT_TOKEN` *(optional)* | `ci-sast.yml` report commits on `main` | fine-grained PAT: *Contents* read/write; needs a ruleset bypass if `main` is protected | reports stay in the run summary only |

`GITHUB_TOKEN` is provided by Actions; image pushes to GHCR and the Scorecard
workflow use it.

## 5. Variables

*Settings → Secrets and variables → Actions → Variables.*

| Variable | Effect |
| -------- | ------ |
| `MAKE_PR_DRAFT=true` *(optional)* | `make-pr-draft.yml` turns every new PR into a draft and asks the author to mark it ready |

## 6. Workflow configuration

Edit the lines marked `CUSTOMISE`:

| File | What to change |
| ---- | -------------- |
| `.github/workflows/release-to-ghcr.yml` | the `matrix.include` list: one `image` / `context` per image you publish. Images land at `ghcr.io/<owner>/<repo>-<image>`; set each package's visibility in *Packages* after the first push. |
| `.github/workflows/ci.yml` → `stack` | the URLs `Call every service through the proxy` checks, once you replace the example services |
| `.github/workflows/ci-sast.yml` → `codeql` | `languages:` (ships with `actions` only); compiled languages may need another `build-mode` |
| `.github/workflows/ci-sast.yml` → `sonarqube` | steps that generate coverage reports |
| `.sast/codeql-config.yml` | `paths:` to your sources |
| `.sast/sonar-project.properties` | `sonar.organization`, `sonar.projectKey`, `sonar.sources`, coverage report paths. In SonarQube Cloud, turn **Automatic Analysis off**. |
| `.github/workflows/check-conventional-commit-pr-title.yml` and `.githooks/check-conventional-commit-msg` | the allowed commit types — keep both lists identical |

Nothing to configure for: `devshell`, `dockerfile-lint`, `compose-lint`,
`workflow-lint`, `zizmor` and `dependencies-audit` (they discover files on
their own), `check-pr-linked-issue.yml`, `openssf-scorecard.yml`.

Keep `ci-required`'s `needs:` list in `ci.yml` in step with your jobs: a job
is only mandatory once it is listed there. When you add a workflow, follow the
rules in `AGENTS.md` and run `just lint-workflows`.

## 7. Your application

- Replace `api/` and `web/` with your services. Give each a `Dockerfile`
  (release image, code copied in) and a `Dev.Dockerfile` (dependencies only;
  `docker-compose.yml` bind-mounts the source for live reload).
- In `docker-compose.yml`, keep the 1-second healthchecks and the `traefik.*`
  labels, or publish `ports:` directly and drop the `proxy` service. Always
  publish with an address (`"127.0.0.1:5432:5432"`); a bare `"5432:5432"`
  listens on every interface. `PROXY_BIND=0.0.0.0` in `.env` shares the app
  on the network.
- Put new environment variables in `.env.example`; secrets get a
  `change-me-…` value so the dev shell generates them.
- Add tools to `packages` in `flake.nix`, or to `nix/tools.nix` when you need
  a version nixpkgs does not have.
- With a database: uncomment the Postgres recipes at the end of the
  `justfile` and make `_pre-nuke` run `just database-dump`, so `just nuke`
  backs up before deleting volumes.

## 8. Check it works

1. Open a PR that closes an issue. `ci-required`, `conventional-title` and
   `linked-issue` must go green and block the merge until they do.
2. Merge it. release-please opens a Release PR; merging that creates a tag,
   and `release-to-ghcr.yml` pushes signed images. Verify one:
   ```bash
   cosign verify ghcr.io/<owner>/<repo>-api:<tag> \
     --certificate-identity-regexp 'https://github.com/<owner>/<repo>/' \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   ```
3. Run `openssf-scorecard.yml` once by hand so the README badge has data.

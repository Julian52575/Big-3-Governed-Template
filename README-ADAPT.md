# Adapting this template

Everything to do after **Use this template** so the dev shell, CI, releases
and governance work in your repository. **`adapt.py`** does most of it in one
pass; this page says what each step changes, and what is left to do by hand.

`adapt.py` uses only the Python standard library (3.9+) and is not part of
the dev shell. Without a host `python3`, run it as
`nix shell nixpkgs#python3 -c ./adapt.py`. The GitHub steps need
[`gh`](https://cli.github.com/) authenticated as a repo admin; without it they
are skipped and the rest still runs.

**Prefer to be walked through it?** A local AI coding agent (Claude Code,
Codex, Copilot, …) opened in this repository can guide you: ask it to *"follow
README-ADAPT.md to set up this repository"*. `AGENTS.md` tells it to do so;
it explains each step, runs `adapt.py` with you, and shows every command
before running it. Secret values are still yours to type into `adapt.py` —
never paste them into the agent's chat.

## Pick how much it asks

| You are… | Run | It asks | Commands |
| -------- | --- | ------- | -------- |
| **trusting**: provide only what it cannot find | `./adapt.py --trust` | only what it cannot detect: the conduct contact and secret values | run without asking |
| **laid-back**: guided through everything | `./adapt.py` | every question, with the detected value as default | each one shown, runs only on `y` |
| **doubtful**: see the commands, run the ones you want | `./adapt.py --print-cmd` (add `--dry-run` to edit no file either) | every question | none run; all printed again at the end, ready to copy |
| **short on time**: everything in one pass | `./adapt.py --accept-cmd` | every question | run without asking |

Every mode runs the local steps, then the GitHub steps, then the final check.
**Already-adapted fields are detected and skipped** — the owner/repo is
replaced, the version is not `0.0.0`, the contact or SonarQube keys are
filled, signing is configured, a secret is set, the ruleset is in place — so
re-running is safe and only asks about what is left. Then review the file
changes with `git diff` and commit them (`git commit -s`).

Other options: a single step flag (`--rename`, `--gh-vars`, …) runs only that
step; `--yes` never asks and prints commands unless `--accept-cmd`;
`--workflow` only checks. `./adapt.py --help` lists them all.

**Commands that change something** (`git config`, `ssh-keygen`, `gh … set`,
`apply-governance.sh`) are always printed before they run. Secret values are
read without echo, passed to `gh` on stdin, and never printed. Read-only
queries (`git remote`, `gh … list`, `gh api` reads) run on their own.

## 1. Local setup (every contributor)

1. Install Nix with flakes ([Determinate installer](https://install.determinate.systems/))
   and, on Linux, `uidmap` for rootless Podman. On macOS, install Podman
   Desktop (or `brew install podman`) and start a machine
   (`podman machine init && podman machine start`).
2. `nix develop` (or `direnv allow`). This creates `.env`, generates every
   `change-me-*` secret, and enables the git hooks.
3. `./adapt.py --signing` sets up SSH **commit signing** for this clone only
   (`git config --local`): pick an existing key or generate one, and
   optionally register it on GitHub as a *Signing Key* through `gh`. The
   `commit-msg` hook rejects unsigned or un-signed-off commits, so also commit
   with `git commit -s`. A project that does not want signing runs
   `git config hooks.requireSignature false` in each clone.
4. `just up -d` and open <http://localhost:8000>.

## 2. Local steps

Each step also runs alone with its flag, and is skipped when already done.

| Flag | Changes | Skipped when | If you skip it |
| ---- | ------- | ------------ | -------------- |
| `--clean` | deletes `.readme-badges/*.json`, `.sast/openssf/SCORECARD.md`, `.sast/report/*` and `CHANGELOG.md`; the workflows regenerate them. The README badge stays empty until the first Scorecard PR is merged (see *Check it works*). | none of them is left | the template's old results are shown |
| `--rename` | replaces `Julian52575/Big-3-Governed-Template` (also URL-encoded) and `OWNER/REPO` (README badge, security-advisory link, …) with the `owner/repo` of `origin`, and sets `"package-name"` in `release-please-config.json` | no reference is left | the badge and vulnerability reports point at the template |
| `--version` | asks for the project's current version (default `0.0.0`) and writes `.release-please-manifest.json` | the version is not `0.0.0` | the first release is computed from `0.0.0` |
| `--contact` | fills `[INSERT CONTACT METHOD]` in `CODE_OF_CONDUCT.md` | the placeholder is gone | nobody to report conduct issues to |
| `--sonar` | fills the SonarQube Cloud keys in `.sast/sonar-project.properties`, defaulting to SonarQube's own (`<owner>`, `<owner>_<repo>`) | both keys are set | the SonarQube job fails once its token is set |
| `--signing` | proposes the four `git config --local` signing commands as one step, then `gh ssh-key add`; defaults to your configured signing key, else `~/.ssh/id_ed25519.pub` | `commit.gpgsign` and `user.signingkey` are set | commits are rejected by the hook |

Still by hand: the README's title, intro, *Customising* section and © line,
and `"release-type"` in `release-please-config.json` (`simple` → e.g. `node`
so `package.json` versions are bumped).

## 3. GitHub steps: `--gh-vars`, `--governance`

The repository created by *Use this template* is enough; nothing has to be
pushed first. When `gh` is missing, not logged in or cannot reach the
repository, a full run skips these steps (and says why); `--gh-vars` or
`--governance` alone stop with an error.

`--gh-vars` asks for each Actions secret and variable below that is **not
set yet**; set ones are left alone. Blank input skips one.

| Name | Kind | Needed for | Scope | If unset |
| ---- | ---- | ---------- | ----- | -------- |
| `RELEASE_PLEASE_GITHUB_TOKEN` | secret, **required** | `release-please.yml` | fine-grained PAT or GitHub App token on this repo: *Contents* and *Pull requests* read/write | release-please fails; with the built-in token instead, releases would not trigger `release-to-ghcr.yml` |
| `SONARQUBE_TOKEN` | secret | `ci-sast.yml` SonarQube job | SonarQube Cloud analysis token | SonarQube is skipped; CodeQL still runs |
| `SAST_REPORT_TOKEN` | secret | `ci-sast.yml` report commits on `main` | fine-grained PAT: *Contents* read/write; needs a ruleset bypass if `main` is protected | reports stay in the run summary only |
| `DISCORD_WEBHOOK_URL` | secret | `notify-discord-review-requested.yml` | a Discord channel webhook URL (*Channel settings → Integrations → Webhooks*, [docs](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks)) | no Discord notification; the job runs and skips its steps |
| `MAKE_PR_DRAFT` | variable | `make-pr-draft.yml` | `true` | new PRs are not turned into drafts |

`GITHUB_TOKEN` is provided by Actions; image pushes to GHCR and the Scorecard
workflow use it.

`--governance` runs `scripts/apply-governance.sh`: the branch ruleset from
`.github/rulesets/main.json`, squash-only merges, read-only default
`GITHUB_TOKEN`, Dependabot, secret scanning, private vulnerability reporting
and the issue labels. Without it, `main` is unprotected and `ci-required`
does not block a merge.

Then, by hand:

- **Organisation** *(if any)*: require 2FA; *Actions → General* → require
  approval for fork pull request workflows.
- **CODEOWNERS** *(optional)*: add `.github/CODEOWNERS`; the ruleset already
  requires code-owner review once it exists.
- **Signed commits on GitHub** *(optional)*: add `{ "type": "required_signatures" }`
  to `rules` in `.github/rulesets/main.json` and re-run `--governance`. Leave
  `SAST_REPORT_TOKEN` unset (or give its account a bypass) — its report
  commits are not signed.
- **SAST as a merge gate** *(optional)*: add `{ "context": "ci-sast-required" }`
  to `required_status_checks` in the same file and re-run `--governance`.

## 4. Check: `./adapt.py --workflow`

Reports `ok`, `warn` or `FAIL` for: the `origin` remote, leftover template
references and results, the manifest version, the Code of Conduct contact,
commit signing and git hooks, every secret and variable above, the SonarQube
keys (when its token is set), the `ci-required` ruleset, the read-only
`GITHUB_TOKEN` default and squash-only merges. Exits 1 if anything fails, so
it can also run in a script.

## 5. Workflow configuration

Edit the lines marked `CUSTOMISE`:

| File | What to change |
| ---- | -------------- |
| `.github/workflows/release-to-ghcr.yml` | the `matrix.include` list: one `image` / `context` per image you publish. Images land at `ghcr.io/<owner>/<repo>-<image>`; set each package's visibility in *Packages* after the first push. |
| `.github/workflows/ci.yml` → `node` | the `service` matrix: one entry per Node.js folder |
| `.github/workflows/ci.yml` → `stack` | the URLs `Call every service through the proxy` checks, once you replace the example services |
| `.github/workflows/ci-sast.yml` → `codeql` | `languages:` (ships with `actions, javascript-typescript`); compiled languages may need another `build-mode` |
| `.github/workflows/ci-sast.yml` → `sonarqube` | steps that generate coverage reports |
| `.sast/codeql-config.yml` | `paths:` to your sources |
| `.sast/sonar-project.properties` | `sonar.organization`, `sonar.projectKey`, `sonar.sources`, coverage report paths. In SonarQube Cloud, turn **Automatic Analysis off**. |
| `.github/workflows/check-conventional-commit-pr-title.yml` and `.githooks/check-conventional-commit-msg` | the allowed commit types — keep both lists identical |

Nothing to configure for: `devshell`, `dockerfile-lint`, `compose-lint`,
`workflow-lint`, `zizmor` and `dependencies-audit` (they discover files on
their own), `openssf-scorecard.yml`.

Keep `ci-required`'s `needs:` list in `ci.yml` in step with your jobs: a job
is only mandatory once it is listed there. When you add a workflow, follow the
rules in `AGENTS.md` and run `just lint-workflows`.

## 6. Your application

- Build on the `frontend/` and `backend/` placeholders, or replace them. Give each a `Dockerfile`
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
- The `db` service is Postgres; change its schema in
  `backend/prisma/schema.prisma`. Without a database, drop `db`, Prisma and
  the `database-*` recipes, and set `_pre-nuke` back to `@true`.

## 7. Check it works

1. Open a PR. `ci-required` must go green and blocks the merge until it does.
2. Merge it. release-please opens a Release PR; merging that creates a tag,
   and `release-to-ghcr.yml` pushes signed images. Verify one (cosign v3+):
   ```bash
   cosign verify ghcr.io/<owner>/<repo>-backend:<tag> \
     --certificate-identity-regexp 'https://github.com/<owner>/<repo>/' \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   ```
3. Run `openssf-scorecard.yml` once by hand so the README badge has data.

<!-- swap `Julian52575/Big-3-Governed-Template` in the badge URL for your own owner/repo. -->
[![OpenSSF Scorecard](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2FJulian52575%2FBig-3-Governed-Template%2Fmain%2F.readme-badges%2Fscorecard-badge.json)](.readme-badges/scorecard-results.json)

# Nix + Just + Rootless Podman — The Big 3, governed

<img width="653" height="758" alt="Big3NixPodJust" src="https://github.com/user-attachments/assets/0044d938-f98a-44a2-9057-2fa8246e9a1a" />

A GitHub **template repository**: install Nix, clone, and you get a
multi-service dev environment that is identical on every Linux or macOS
machine — plus hardened CI and repository governance out of the box.

## Quick start

```bash
nix develop        # enter the dev shell (first run downloads the tools)
just up -d         # start the stack in the background
just               # list every command
```

| URL | goes to |
| --- | ------- |
| <http://localhost:8000/> | `web` — nginx serving `web/index.html` |
| <http://localhost:8000/api/> | `backend` — Python JSON API from `api/` |
| <http://localhost:8080/> | Traefik dashboard (local only) |

Making your own repo from it? Click **Use this template**, then work through
**[Adapt-Readme.md](Adapt-Readme.md)**.

## The stack

- **[Nix](https://nixos.org/)** — `flake.nix` lists the tools, `flake.lock`
  pins them by hash. Everyone (and CI) gets the same binaries; nothing is
  installed globally. See [Nix flakes](https://nixos.wiki/wiki/Flakes).
- **[Just](https://just.systems/man/en/)** — the project's commands, named and
  documented in the `justfile`.
- **Rootless [Podman](https://docs.podman.io/)** + compose — the whole stack
  from `docker-compose.yml`, no daemon, no `sudo`.
- **[Traefik](https://doc.traefik.io/traefik/)** — one entrypoint on
  `:8000`, routing by `traefik.*` labels on each service (`/` → web, `/api` →
  backend). Add a service + two labels and it is routed.

### Requirements

- [Nix](https://install.determinate.systems/) with flakes enabled.
- **Linux:** `newuidmap`/`newgidmap` (the `uidmap` package) and a
  `/etc/subuid` + `/etc/subgid` entry for your user.
- **macOS:** Podman from the host ([Podman Desktop](https://podman-desktop.io/)
  or `brew install podman`), with `podman machine init && podman machine start`.

Ubuntu in two commands:

```bash
sudo apt install uidmap
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Optional: [direnv](https://direnv.net/) + [nix-direnv](https://github.com/nix-community/nix-direnv)
and `direnv allow` load the shell automatically on `cd`.

### What the shell does

1. Creates `.env` from `.env.example` and replaces every `change-me-*` value
   with a random secret (once).
2. Routes every container command through rootless Podman and the pinned
   `podman-compose`.
3. Points Podman at the in-repo config in `.config/podman/` — nothing under
   `/etc` or `~` is changed, except a `policy.json` symlink if none exists.
4. Keeps container storage in `./.containers/`, or under
   `~/.cache/podman-storage/` when the repo sits on a network filesystem
   (WSL2 drvfs, NFS, …). Override with `PODMAN_STORAGE_DIR`.
5. Exposes a Docker-compatible API socket as `DOCKER_HOST` (needed by
   Traefik). Skip with `PODMAN_NO_SOCKET=1`.
6. Enables the git hooks in `.githooks/` (Conventional Commit + signed-off,
   signed commits — see [CONTRIBUTING.md](CONTRIBUTING.md)).

### Just commands

| command | purpose |
| ------- | ------- |
| `just up [-d]` | start the stack (`-d` recommended: Ctrl-C on an attached `podman-compose up` can leave processes behind) |
| `just down` | stop the stack, keep volumes |
| `just ps` / `just logs [svc]` | status / follow logs |
| `just exec <svc> <cmd…>` / `just sh <svc>` / `just attach <svc>` | run a command / shell / attach to a running service |
| `just rebuild <svc>` | rebuild one service from scratch, the rest keep running |
| `just rm` | stop the stack and delete its images (next `up` rebuilds) |
| `just nuke` | also delete volumes (asks first; refuses on `main` or a release tag unless `NUKE_ANYWAY=1`) |
| `just lint-workflows` | actionlint + zizmor + schema check, as CI does |
| `just database-dump` / `database-pipe <file>` | Postgres backup/restore — commented out until you add a `db` service |

## Governance

The rules (issue → branch → PR, Conventional Commits, required checks) are in
**[CONTRIBUTING.md](CONTRIBUTING.md)**. They are enforced by repository
settings that one script applies, using an authenticated [`gh`](https://cli.github.com/):

```bash
scripts/apply-governance.sh [owner/name]
```

It is safe to re-run, and sets:

- **Branch ruleset** from `.github/rulesets/main.json`: PR with 1 approval
  (code owners when a `CODEOWNERS` exists), resolved threads, the single
  required check `ci-required` on an up-to-date branch, linear history, no force-push or deletion, no bypass. It can also be
  imported by hand: *Settings → Rules → Rulesets → Import*.
  See [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets).
- **Merges:** squash only, PR title as the commit, branches auto-deleted,
  auto-merge allowed.
- **Actions:** read-only default `GITHUB_TOKEN`.
- **Security** (best-effort, depends on your plan): Dependabot alerts and
  fixes, secret scanning + push protection, private vulnerability reporting.
- The issue labels used by the issue forms.

To also *enforce* signed commits on GitHub, add `{ "type": "required_signatures" }`
to the ruleset's `rules` and re-run. For an organisation, also require 2FA and
approval for fork PR workflows.

## CI and automation

All workflows follow the same hardening: actions pinned to a commit SHA
(`# vX.Y.Z` comment, maintained with `pin-github-action`), least-privilege
`permissions:`, `timeout-minutes`, `step-security/harden-runner`,
`persist-credentials: false`, and no `${{ … }}` inside `run:`. Background:
[GitHub's security hardening guide](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions).

| Workflow | Does |
| -------- | ---- |
| `ci.yml` | flake evaluation, hadolint, compose check, actionlint, zizmor, [osv-scanner](https://google.github.io/osv-scanner/) dependency audit, boots the stack and calls every route; all gated by the single `ci-required` job |
| `ci-sast.yml` | [CodeQL](https://codeql.github.com/docs/) always, [SonarQube Cloud](https://docs.sonarsource.com/sonarqube-cloud/) when its token is set; see [`.sast/README.md`](.sast/README.md) |
| `check-conventional-commit-pr-title.yml` | PR title is a Conventional Commit (advisory, not required) |
| `openssf-scorecard.yml` | weekly [OpenSSF Scorecard](https://scorecard.dev/); results go to the `openssf-update` branch and an issue with a one-click PR link. The README badge reads the merged result from `main`. |
| `release-please.yml` | keeps a [release-please](https://github.com/googleapis/release-please) Release PR open; merging it tags and publishes the release |
| `release-to-ghcr.yml` | on release: builds each image, pushes to GHCR with SBOM + provenance, signs keyless with [cosign](https://docs.sigstore.dev/cosign/signing/overview/) |
| `make-pr-draft.yml` | opt-in (`MAKE_PR_DRAFT=true` variable): new PRs start as drafts |

`.github/actions/setup-devshell` installs Nix and caches the store in the
GitHub Actions cache (no account needed). For a cache shared with your
machine, swap it for [Cachix](https://docs.cachix.org/continuous-integration-setup/github-actions).

## Layout

```
flake.nix, flake.lock, nix/tools.nix   dev shell and pinned tools
justfile                               project commands
docker-compose.yml                     Traefik proxy + example web + backend
web/, api/                             example services: Dockerfile (release) + Dev.Dockerfile (live reload)
.config/podman/                        rootless Podman config (storage.conf is generated)
.env.example                           template for .env
.githooks/                             commit-msg checks
.github/workflows/, .github/actions/   CI, release and audit workflows
.github/rulesets/main.json             branch ruleset
.github/ISSUE_TEMPLATE/, PULL_REQUEST_TEMPLATE.md
.sast/                                 SAST config, report scripts, committed reports
scripts/apply-governance.sh            applies the repository settings
release-please-config.json, .release-please-manifest.json
docs/Troubleshoot.md                   incident log
Adapt-Readme.md, CONTRIBUTING.md, AGENTS.md
```

## Customising

- **Tools:** add them to `packages` in `flake.nix` (or `nix/tools.nix` for
  versions nixpkgs lacks). Bump nixpkgs by editing `nixpkgs.url`, then
  `nix flake update`.
- **Services:** replace `web` and `backend`. Keep the pattern: a release
  `Dockerfile`, a `Dev.Dockerfile` with the source bind-mounted, 1-second
  healthchecks, and `traefik.*` labels (or `ports:` bound to `127.0.0.1`).
  After editing a `Dev.Dockerfile`, run `just rebuild <svc>`.
- **No Traefik:** remove the `proxy` service and the labels, publish ports
  directly.

## AI usage disclosure

Parts of this repository were drafted with Claude Code. Every AI-assisted
change is reviewed and tested by a human, and carries a `Co-Authored-By:`
trailer naming the assistant.

---

© 2026 Julian Bottiglione &lt;julian.bottiglione@epitech.eu&gt;

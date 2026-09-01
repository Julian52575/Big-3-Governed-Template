# Nix + Just + Rootless Podman — The Big 3, governed

<img width="653" height="758" alt="Big3NixPodJust" src="https://github.com/user-attachments/assets/0044d938-f98a-44a2-9057-2fa8246e9a1a" />

A GitHub **template repository**: clone it, install two dependencies, and you have a
full multi-service dev environment identical on every (Linux) machine that can be expanded to **ANY** kind of project.  

This is the **governed** variant of the **Big-3-Template**: the same
out-of-the-box Nix + Just + rootless Podman stack, plus **repository
governance** — See [Governance](#governance). 

## Why this stack

**[Nix](https://nixos.org/) — `flake.nix` + `flake.lock` — one reproducible
toolbox.**
`flake.nix` lists the tools this project needs (Podman, Just, compose, …).
`flake.lock` pins each of them to an exact version by hash, so `nix develop`
drops you into a shell where those *same* binaries are on `PATH` — for you,
for a teammate, for CI, today and in two years. Nothing is installed globally
and nothing leaks between projects; leave the shell and the tools are gone.
No "first install X, then the right version of Y" onboarding.

```bash
nix develop                   # enter the shell: flake.lock's tools on PATH
nix develop -c "just up"      # run one command in it without staying
nix flake metadata            # show exactly what's pinned
nix flake update              # bump every input, rewrite flake.lock
```

**[Just](https://github.com/casey/just) — the project's commands in one
place.**
Rather than memorising long `podman` / `compose` invocations, you get named
shortcuts in the `justfile`: `just up`, `just logs`, `just sh web`,
`just nuke`. Running `just` alone lists them with descriptions. Everyone types
the same short command and gets the same behaviour.

```bash
just                  # list every recipe with its description
just up -d            # start the stack detached
just logs web         # follow one service's logs
just sh backend       # open a shell in a running container
```

**Rootless [Podman](https://podman.io/) + compose — the whole stack from one
file.**
`docker-compose.yml` describes every service and how they connect; `just up`
starts them together on a private network, `just down` stops them. *Rootless*
means no background daemon and no `sudo` — containers run as your user and
can't touch the host. Services are disposable: recreate one in seconds, reset
its data by dropping a volume instead of reinstalling anything on your
machine.

```bash
just up -d               # bring up every service in docker-compose.yml
just ps                  # what's running
podman stats             # live CPU/memory per container (no daemon, no sudo)
just rm && just up -d     # rebuild images from source, then restart
just nuke                # remove containers + volumes for a clean slate
```

**BONUS:** **[Traefik](https://traefik.io/) — one clean entrypoint instead of a pile of
ports.**
Normally each service you want to reach needs its own published port
(`localhost:8001`, `:8002`, …), with the CORS friction that follows. Traefik
sits in front and routes by simple `traefik.*` labels on each container, so
everything is reachable under one URL on tidy paths (`/` → web,
`/api` → api). Add a service, add two labels, it is routed — no port
bookkeeping. Traefik watches the Podman socket, so starting or stopping a
service updates routing on its own, the way an ingress does in production.

```bash
curl localhost:8000/            # -> web
curl localhost:8000/api/hello   # -> backend, prefix stripped to /hello
curl -s localhost:8080/api/http/routers | jq '.[].rule'   # discovered routes
# dashboard UI: browse http://localhost:8080/
```

## Use this template

Click **“Use this template”** on GitHub (or `gh repo create <name> --template
<this-repo>`), then:

```bash
cp .env.example .env          # adjust as needed
nix develop                   # enter the dev shell (first run compiles the closure)
just up -d                    # start the stack in the background
scripts/apply-governance.sh                 # see Governance. UPDATE THE GITHUB REPO'S SETTINGS
```

The stack is a Traefik `proxy` in front of two throwaway example backends —
keep the proxy, replace the backends:

| URL | goes to |
| --- | ------- |
| <http://localhost:8000/> | `web` — nginx serving `web/index.html` |
| <http://localhost:8000/api/> | `backend` — Python JSON service built from the `api/` folder |
| <http://localhost:8080/> | Traefik dashboard (insecure, local only) |

Traefik routes by the `traefik.*` labels on each service in
`docker-compose.yml`, read through the Podman socket the shell exports as
`$DOCKER_SOCK`.

### With direnv (optional, recommended)

Install [`direnv`](https://direnv.net/) +
[`nix-direnv`](https://github.com/nix-community/nix-direnv), then:

```bash
direnv allow
```

The dev shell now loads automatically whenever you `cd` into the repo.

## Requirements

- Linux with [Nix](https://nixos.org/download/) and flakes enabled
  (`experimental-features = nix-command flakes` in `nix.conf`, or use the
  [Determinate installer](https://install.determinate.systems/)).
- Rootless Podman needs `newuidmap`/`newgidmap` (the `uidmap` package on most
  distros) and a `/etc/subuid` + `/etc/subgid` entry for your user.

Shorten in a few install command for Ubuntu:
```
sudo apt install uidmap
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
Close your terminal and open a new one: it's installed !  

## What you get in the shell

Entering the shell (`nix develop` / direnv):

1. Loads `.env` if present.
2. Points Podman at the in-repo config (`.config/podman/`) via
   `CONTAINERS_CONF` / `CONTAINERS_STORAGE_CONF` / `CONTAINERS_REGISTRIES_CONF`,
   and symlinks `policy.json` into `~/.config/containers/` only if nothing is
   there yet. Nothing under `/etc` is touched.
3. Picks a container storage root. Default is `./.containers/`. If the repo
   sits on a network/virtualised filesystem (WSL2 `drvfs`, NFS, CIFS, sshfs)
   — where Podman's overlay driver hits obscure mount errors — it falls back
   to `~/.cache/podman-storage/<project>/`. Override with `PODMAN_STORAGE_DIR`.
4. Starts a rootless Docker-API socket and exports `DOCKER_HOST` (and
   `DOCKER_SOCK`, the bare path, which `docker-compose.yml` bind-mounts into
   Traefik), so `docker compose`, testcontainers, lazydocker, etc. work. It reuses a
   running socket or a `systemd --user podman.socket` if available, otherwise
   spawns a detached `podman system service` that is killed when the shell
   exits. Set `PODMAN_NO_SOCKET=1` to skip this (CI/headless).
5. Points `git` at `.githooks/`, enabling the `commit-msg` hook (which execs
   `.githooks/check-conventional-commit-msg`) that checks each message is a
   [Conventional Commit](https://www.conventionalcommits.org/)
   (`<type>[(scope)][!]: description`, subject lower-case, no trailing
   period). Local feedback only — `git commit --no-verify` skips it.

## Just commands

| command | purpose |
| ------- | ------- |
| `just` | list all recipes |
| `just up [args…]` | start the stack; pass `-d` to run detached |
| `just down` | stop the stack, keep volumes |
| `just rm` | stop the stack and drop its built images (next `just up` rebuilds) |
| `just ps` | container status |
| `just logs [svc]` | follow logs (Ctrl-C stops following, not the container) |
| `just exec <svc> <cmd…>` | run a command in a running service container |
| `just sh <svc>` | interactive shell in a running service container |
| `just attach <svc>` | attach this terminal to a service's live stdio (detach: Ctrl-C or ctrl-p ctrl-q) |
| `just nuke` | stop stack + delete its volumes and local images (asks first) |

> `just up` runs `compose up` in the foreground. With `podman-compose`,
> stopping an attached `up` with Ctrl-C can leave a runaway `podman start -a`
> process behind — prefer `just up -d` and follow output with `just logs`.

## Governance

On top of the dev-shell stack, this template ships **repository governance**. 
It is all standard Git/GitHub configuration, no external services needed. 

### Conventional Commits

Commits and PR titles follow [Conventional Commits](https://www.conventionalcommits.org/):
`<type>[(scope)][!]: description`, with the description starting lower-case and
carrying no trailing period. Both ends enforce the **same rule set** — the same
type list, the same optional scope and `!`, the same subject pattern.

- **Local (advisory):** the `.githooks/commit-msg` hook — auto-enabled by the
  flake `shellHook` on `nix develop`, which points `core.hooksPath` at
  `.githooks/` — execs `.githooks/check-conventional-commit-msg`, which rejects
  a malformed message as you write it. Bypassable with `git commit
  --no-verify`, so it is only a convenience.
- **CI (enforced):** `.github/workflows/check-conventional-commit-pr-title.yml`
  validates the **PR title** via [`amannn/action-semantic-pull-request`](https://github.com/amannn/action-semantic-pull-request).
  On a squash merge the PR title is the commit that lands on `main`, so this is
  the real gate. A bad title is fixed by editing it in the GitHub UI (the check
  re-runs on `edited`) — no history rewrite.

Keep the two in sync when you customise: the type list lives in both
`.githooks/check-conventional-commit-msg` and
`.github/workflows/check-conventional-commit-pr-title.yml`.

Make your developers refer to the [Conventional Commits Cheatsheet](https://gist.github.com/qoomon/5dfcdf8eec66a051ecd85625518cfd13#commit-message-formats)   
or the [Official Summary](https://www.conventionalcommits.org/en/v1.0.0/#summary) for convenience. 

### Issue templates

`.github/ISSUE_TEMPLATE/` ships four [issue forms](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository)
— structured fields rather than a blank box — and `config.yml` turns off blank
issues, so every issue arrives in one of these shapes. Each form auto-applies a
type label plus `needs-triage`, and each opens with a "not a duplicate"
pre-submit check.

| Form | For | Key fields |
| ---- | --- | ---------- |
| **Feature** | a new capability or an enhancement | Problem (the need, not the solution), Proposed solution, Alternatives, rough scope |
| **Bug** | incorrect behaviour in something that exists | What's wrong, Steps to reproduce (from a clean checkout), Expected vs actual, Environment (`git rev-parse HEAD`), Logs |
| **R&D** | a research spike or open design question | Question/hypothesis, Definition of done, Context and constraints, rough scope |
| **Debt** | it works, but the code or design carries a shortcut | The shortcut (and where), Cost it carries, Proposed cleanup, interest accrual |

Security reports are routed away from public issues: `config.yml` links to
**private vulnerability reporting** instead (replace `OWNER/REPO` after using the
template).

The forms are the front half of the workflow: an issue defines the *problem*, a
PR closing it carries the *solution*. That split is why the PR template below can
stay so small.

### Pull request template

`.github/PULL_REQUEST_TEMPLATE.md` pre-fills every new PR. It is deliberately
short: the [issue forms](.github/ISSUE_TEMPLATE/) already capture the *problem*
(what's wrong, repro, proposed change, alternatives), and the Conventional-Commit
PR title already encodes the *type* of change. Repeating any of that in the PR
body is noise. Every PR is expected to close an issue, so the template only asks
for what a **reviewer** can't get from the linked issue or the diff:

| Field | Why it's there |
| ----- | -------------- |
| `Closes #NNN` | Required. Links the issue and auto-closes it on merge. Branch and push first if you like, but the issue must exist before the PR is opened. |
| What changed | One or two lines on the shape of the diff — the "why" stays in the issue. |
| How it was verified | The steps a reviewer repeats to trust the change; not something the issue knows. |
| Risk / rollback | Breaking changes, migrations, blast radius. "None" is a valid answer. |
| Checklist | "meant to close an issue" plus tests / docs — the easily-forgotten parts. |

### Branch ruleset & repository settings

The template ships prepared settings as json and a script to apply it directly:

- **`.github/rulesets/main.json`** — the main branch ruleset, in GitHub's ruleset
  export format.
- **`scripts/apply-governance.sh`** — applies the ruleset *and* the repo-level
  merge/security settings via the GitHub CLI.

**Option A — one command (recommended).** With [`gh`](https://cli.github.com/)
authenticated as an admin of the new repo:

```bash
scripts/apply-governance.sh                 # current repo
scripts/apply-governance.sh owner/name      # or an explicit repo
```

Re-running is safe: it deletes the old `Auto Big-3-Governance main ruleset` ruleset and recreates it, then
re-applies the same settings. 
You can access the settings/rules page to delete the rule at anytime. 

**Option B — GitHub UI.** Import the ruleset by hand:
*Settings → Rules → Rulesets → New ruleset → Import a ruleset* → pick
`.github/rulesets/main.json`. Then set the merge and security items from the
checklist below yourself.

#### What gets configured

**Ruleset on the default branch** (`.github/rulesets/main.json`):

| Rule | Value | Why |
| ---- | ----- | --- |
| Require a pull request | 1 approval, dismiss stale approvals on push | no direct pushes to `main` |
| Require review from Code Owners | on | routes review to owners once you add a `CODEOWNERS` file |
| Require conversation resolution | on | no merging over unresolved threads |
| Require status checks | `ci-required`, `conventional-title`, strict (branch up to date) | `main` only ever sees green, rebased commits |
| Require linear history | on | pairs with squash-only merges — readable `main` |
| Block force pushes | on | history on `main` is append-only |
| Restrict deletions | on | `main` can't be deleted |
| Bypass list | empty | the rules apply to everyone, admins included |

> The status-check names are job IDs in the workflows. `ci-required` is an
> aggregator job in `.github/workflows/ci.yml` that `needs` every other job in
> that workflow, so the ruleset names one stable check instead of each job —
> add a job to its `needs` list to make it required. `conventional-title` is the
> job in `.github/workflows/check-conventional-commit-pr-title.yml`. Renaming a
> job that `ci-required` lists fails the workflow loudly; only `ci-required` and
> `conventional-title` themselves must stay in sync with `main.json`.

**Repository merge settings** (set by the script; *Settings → General → Pull
Requests* in the UI):

| Setting | Value | Why |
| ------- | ----- | --- |
| Allow squash merging | on, **commit title = PR title** | the Conventional-Commit PR title becomes the commit on `main` |
| Allow merge commits | off | one commit per PR, no merge bubbles |
| Allow rebase merging | off | keeps squash as the only path |
| Automatically delete head branches | on | no stale branch buildup |
| Always suggest updating branches | on | fewer “branch out of date” stalls |
| Allow auto-merge | on | queue a PR to merge itself once checks pass |

**Security settings** (set by the script; *Settings → Code security* in the UI):

| Setting | Notes |
| ------- | ----- |
| Dependabot alerts + automated security fixes | free on every repo |
| Secret scanning + push protection | free on **public** repos; private needs GitHub Advanced Security |
| Private vulnerability reporting | free on every repo |

**Actions settings** (set by the script; *Settings → Actions → General* in the UI):

| Setting | Value | Why |
| ------- | ----- | --- |
| Default `GITHUB_TOKEN` permissions | read-only | workflows get a read token unless they opt in with their own `permissions:` block |

The script treats the security calls as best-effort — on a plan that doesn't
include one it prints a warning and moves on.

#### BONUS: Org-level (can't be scripted per-repo)

Set these once for the organisation, not the repo:  
**require 2FA for all members**, and under *Actions → General* set **fork pull request workflows** to require approval. 

## Layout

```
flake.nix                 dev shell: tool pins + Podman bootstrap shellHook
.envrc                    direnv: `use flake`
justfile                  container-lifecycle commands
docker-compose.yml        the stack: Traefik proxy + example web + backend
web/                      `web` image source (nginx + static index.html)
api/                      `backend` image source (python:slim + stdlib app.py)
.config/podman/
  containers.conf         runtime = crun, default transport
  registries.conf         unqualified image lookups -> docker.io
  policy.json             image trust policy (symlinked into ~ by the shell)
  storage.conf            generated per-machine on shell entry (gitignored)
.env.example              copy to .env
.containerignore          build-context excludes (.dockerignore -> symlink)
.githooks/commit-msg           dispatcher git runs; execs the check script below
.githooks/check-conventional-commit-msg   local Conventional Commits check (enabled by the shellHook)
.github/actions/setup-devshell/   composite action: checkout-then-install-Nix, shared by workflows
.github/workflows/ci.yml       flake eval + compose lint; `ci-required` aggregator gate
.github/workflows/check-conventional-commit-pr-title.yml  PR title must be a Conventional Commit
.github/workflows/check-pr-linked-issue.yml  every PR must close at least one issue
.github/rulesets/main.json     default-branch ruleset, in GitHub export format
scripts/apply-governance.sh    apply the ruleset + merge/security settings via `gh`
```

## Customising

- **Add tools**: put them in `packages` in `flake.nix`.
- **Replace the app**: the `web` and `backend` services (built from `web/`
  and `api/`) are throwaway demos — swap in your own images or `build:`
  contexts and adjust the `traefik.*` labels. Drop either if you only need one.
- **Add a service**: give it `traefik.enable=true` + a router rule label to
  put it behind the proxy, or a `ports:` mapping to expose it directly.
- **Drop Traefik**: remove the `proxy` service and the `traefik.*` labels,
  and publish each service's `ports:` directly.
- **Rebuild after editing `web/` or `api/`**: `just rm; just up`
  (`podman-compose`'s `--build` often misses a changed `COPY`; `just rm`
  deletes the built images so `up` rebuilds them from scratch).
- **Bump nixpkgs**: change the `nixpkgs.url` ref in `flake.nix`, then
  `nix flake update`.
- Rename this file's heading and delete this section once you've made it yours.

---

© 2026 Julian Bottiglione &lt;julian.bottiglione@epitech.eu&gt;

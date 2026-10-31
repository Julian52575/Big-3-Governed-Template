# Feedback on Big-3-Governed-Template

Written after adapting the template to Prompter, a private, local web app
(the "Prompt Builder" spec). The deliverable is **one self-contained HTML
file** (Vite + Preact + TypeScript, opened from `file://`). There is no
server, no database and no container image to ship. The adaptation was done
by an AI agent (Claude Code), with the user's spec and the request to "drop
what is unnecessary".

Result: the governance and CI hardening carried over unchanged. Removing the
demo stack, however, took edits in about 15 files, because the placeholders
are referenced from many places.

## What worked well

- **Workflow hardening is a good base.** Pinned SHAs, harden-runner,
  `persist-credentials: false`, least-privilege `permissions:` and the
  `env:` rule for `${{ }}` made new jobs easy to write correctly. Copying an
  existing job and changing its steps was enough.
- **The `ci-required` aggregator.** Adding the `app` and `e2e` jobs and
  removing `node` meant editing one `needs:` list, and the ruleset was left
  alone.
- **zizmor caught a real problem.** A release job I wrote used
  `actions/setup-node` with `cache: npm`, which zizmor flags as cache
  poisoning (high). The fix (`package-manager-cache: false`) is now in
  `release-build.yml`. This check alone justifies keeping zizmor in CI.
- **`just lint-workflows` locally.** actionlint, zizmor and check-jsonschema
  gave the same verdict as CI, before pushing.
- **The commit hooks.** Signed, signed-off Conventional Commit enforcement
  worked on the first commit with no setup beyond `git commit -s`.
- **Compose conventions.** Named volumes, the 1-second healthcheck and
  publishing on `127.0.0.1` were easy to keep for a single dev container.
- **`AGENTS.md` / `README-ADAPT.md`** told the agent what each piece is for,
  which made it clear what could be dropped safely.

## Main problem: the demo stack is spread across the repository

The template ships Traefik + React frontend + Express/Prisma backend +
Postgres. For a project with no backend, removing it was not a matter of
deleting `backend/` and the `db` service. References had to be found and
fixed in:

| File | What referenced the demo stack |
| ---- | ------------------------------ |
| `docker-compose.yml` | proxy, db, backend, Traefik labels |
| `justfile` | `database-dump`, `database-pipe`, `_ensure-db`, `_pre-nuke` → `database-dump`, `compose-diagnostic`, the `rebuild backend` example |
| `.env.example` | `POSTGRES_*`, `PROXY_*` |
| `flake.nix` | description, Traefik comments on `DOCKER_SOCK` |
| `.github/workflows/ci.yml` | `node` matrix (`backend`, `frontend`), Prisma step, `stack` job calling `/api/*` and the Traefik dashboard |
| `.github/workflows/release-to-ghcr.yml` | image matrix for `backend` and `frontend` |
| `.github/workflows/release-please.yml` | messages pointing to `release-to-ghcr.yml` |
| `scripts/compose_diagnostic.py` | Traefik dashboard and route checks |
| `.sast/sonar-project.properties`, `.sast/codeql-config.yml` | `backend/` paths |
| `.gitignore` | `db_backup_*` |
| `README.md`, `CONTRIBUTING.md`, `README-ADAPT.md` | URLs, tables, cosign example, Prisma instructions |
| `AGENTS.md` | describes `backend/` as a placeholder |

Nothing broke silently, but only because the agent grepped for `backend`,
`traefik`, `postgres`, `ghcr`, `database` and `prisma` across the repository.
A human adapting by hand would likely miss some (the `_pre-nuke` hook that
dumps a database which no longer exists, for example).

**Suggestions:**

1. Give `adapt.py` a profile option, e.g. `--profile static|web|fullstack`,
   or separate `--drop-backend`, `--drop-db`, `--drop-proxy` and
   `--drop-images` flags. Each would remove the files, recipes, env keys, CI
   jobs and doc sections it owns.
2. Until then, add a **"Removing parts of the demo stack"** checklist to
   README-ADAPT.md listing every file above per component (database, backend,
   proxy, image release).
3. Mark the demo-only lines with a grep-able tag such as `# DEMO-STACK`, so
   `grep -rn DEMO-STACK` shows everything to review.

## Other findings

### `compose_diagnostic.py` is tied to Traefik

The script checks the Traefik dashboard and routes. Without the proxy it
reports false problems, so I deleted it along with its recipe. Making the
Traefik checks conditional (skip them when there is no `proxy` service)
would keep it useful for any compose stack.

### The release path assumes container images

`release-to-ghcr.yml` is the only publish step, and `release-please.yml`'s
messages refer to it by name. Many projects ship something other than an
image (a static file, a binary, a package). I replaced it with
`release-build.yml`: on `release: published` (plus `workflow_dispatch` with
a tag input) it checks out the tag, tests, builds and runs
`gh release upload`. It is a generic "attach build artifacts to the release"
workflow and could ship in the template as the alternative to the GHCR
workflow. The note in `release-please.yml` that the PAT is needed so that
releases trigger other workflows applies to it unchanged, which is a good
sign.

### The `stack` CI job is hard to reuse

Its checks are hard-coded calls through the proxy (`/`, `/api/health`,
`/api/items`, the dashboard). For a single dev container I reduced it to
`up --wait` plus one `curl`. Driving it from a small list (URL plus expected
substring), or from the compose healthchecks only, would make it work for any
project without editing the job.

### No browser-test pattern

The spec required Playwright and axe-core. The template has nothing for
browser tests, so the `e2e` job (Playwright browser install, artifact upload
of traces on failure) was written from scratch. An optional `e2e` job
template would be welcome for any web frontend.

### Host Node.js is still needed for some tasks

The template's model is "tools run in containers". `just build`, `test` and
`lint` work that way (`compose run --rm --no-deps -T frontend …`), and
recipes like these would be a useful addition to the template itself.
Playwright, however, needs browsers on the host (or a dedicated image), so
`just e2e` needs host Node.js. A pinned `nix/nodejs.nix` would close this
gap; the DokKodi report already noted that adding Node takes one file.

### `AGENTS.md` is written for the template repository

It says so itself and asks the agent to tell the user to rewrite it. That
works, but after adaptation the file still documents placeholders that no
longer exist. `adapt.py` could swap in a project-oriented `AGENTS.md`
skeleton that keeps only the rules that still apply (commits, workflow
hardening, Nix pinning).

## Small nits

- `frontend/vite.config.ts` proxied `/api` to `localhost:3000`, the backend's
  port, which is misleading once there is no backend.
- With Vite 8, importing a local `.ts` plugin without an extension triggers
  a `configLoader: 'native'` warning; the template's config would hit it as
  soon as a local plugin is added.
- `.gitignore` entries for `db_backup_*` and `.compose-diagnostic-*` linger
  after the related features are removed (another case for profile-aware
  cleanup).
- The README's "Customising" section explains how to drop Traefik but not
  how to drop the backend or the database.

## Suggested priority

1. A checklist (or `adapt.py` profiles) for removing the database, backend,
   proxy and image release. This was the biggest time cost.
2. A generic `release-build.yml` (attach artifacts to the release) next to
   `release-to-ghcr.yml`.
3. A data-driven `stack` job and a `compose_diagnostic.py` that works
   without a proxy.
4. Optional extras: `just build/test/lint` container recipes, an `e2e` job
   template, a pinned Node.js in the dev shell.

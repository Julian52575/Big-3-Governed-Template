# Feedback on Big-3-Governed-Template

Written after adapting the template to a project that is not a container
stack: DokKodi, a Tauri desktop app plus an Expo Android app. Most of the
governance and DevOps tooling carried over unchanged. The friction came from
how deeply the template assumes a Podman/Compose/web-services architecture.

## What worked well

- **Governance and CI hardening** (ruleset, `ci-required` aggregator, pinned
  actions, harden-runner, zizmor, Conventional Commit hooks, SAST workflow,
  Scorecard) were reusable as-is. This is the template's real value.
- **One pinned `nix/<tool>.nix` per tool** is easy to copy: adding Node took
  one file and one line in `tools.nix`.
- **Dev-shell `.env` handling** (`change-me-*` secret generation, carrying over
  new keys) is generic and worth keeping.
- **`ci-required` with a `needs:` list** makes adding or removing jobs simple.
- **Reading the docs was enough.** `AGENTS.md` and `README-ADAPT.md` told an AI
  agent what to look for.

## Main problem: the container stack is not optional

The template presents itself as governance plus tooling, but Podman, Compose,
Traefik, Postgres and Prisma are wired through almost every file. Dropping
them meant editing `flake.nix`, `justfile`, `ci.yml`, `release-to-ghcr.yml`,
`.env.example`, `.gitignore`, `.config/`, `.containerignore`, `.hadolint.yaml`,
`scripts/compose_diagnostic.py`, three docs and `check-jsonschema.nix` (whose
comment mentions `podman-compose`).

Suggestions:

1. **Split into layers.** A "core" (governance, hooks, CI hardening, SAST,
   release-please, Nix tool pinning) and an optional "podman-stack" layer.
   `adapt.py` could ask which layers to keep and delete the rest.
2. **Split `flake.nix`.** The ~150-line Podman `shellHook` (storage root, API
   socket, network-fs detection) could live in `nix/podman-shell.nix`, imported
   only when wanted. Today, removing it means rewriting the whole file.
3. **Split `justfile` into modules** (`just` supports `mod`): `container.just`,
   `database.just`, and a small core with `lint-workflows`.
4. **Tag container-only CI jobs.** `dockerfile-lint`, `compose-lint` and `stack`
   are in `ci-required.needs` next to the generic jobs. Putting them in a
   separate workflow, or marking them with a clear `# CONTAINER STACK` comment
   block, would make removal a clean cut.
5. **Add a "not a container project" path to `README-ADAPT.md`.** It currently
   lists `dockerfile-lint` and `compose-lint` under "nothing to configure", and
   says nothing on removing them.

## Other findings

- **Template identity leaks into adapted repos.** After `adapt.py --rename`,
  some template wording stays:
  - `scripts/apply-governance.sh` still says "this template" and prints
    `Next: ./adapt.py --gh-vars` at the end.
  - The ruleset is named "Auto Big-3-Governance main ruleset" in both
    `main.json` and the script.
  - The README title, intro and layout are left to the user, as documented.
  - `.github/actions/setup-devshell/action.yml` says "clones this template".
  - `release-please.yml` messages tell the user to run `./adapt.py --gh-vars`.

  Making `adapt.py --rename` cover these, or a final "template residue" check
  in `--workflow`, would help. Better still, an `adapt.py --finish` that
  deletes `adapt.py`, `README-ADAPT.md` and the template wording once the
  project is adapted.
- **`adapt.py` and `README-ADAPT.md` have no retire step.** For a real project
  they are dead weight and `AGENTS.md` keeps telling agents to run them. A
  documented "you are done, delete these" step would help.
- **`AGENTS.md` is split by "template repo" vs "created from template".** That
  made sense, but an adapted repo has to rewrite the file by hand. A short
  `AGENTS.project.md` stub, swapped in by `adapt.py`, would be tidier.
- **Hardcoded Node assumptions.** The `node` CI job assumes a Node.js service
  with `lint` and `test` scripts and a `prisma` special case. Using
  `npm run --if-present` and a matrix of folders (done here) is more reusable.
  The `matrix.service == 'frontend'` build condition is another hardcoded name.
- **Matrix names are hardcoded in two places.** `ci.yml` and
  `release-to-ghcr.yml` each list services separately; a single source (for
  example, discovering folders with a `package.json`) would avoid drift.
- **`.release-please-manifest.json` ships as `1.0.0`** and `CHANGELOG.md` is
  committed with the template's history; `adapt.py --clean` handles this, but
  a repo that skips it gets a wrong first release.
- **Committed Scorecard results** (`.readme-badges/`, `.sast/openssf/`) are the
  template's own and are deleted by `--clean`. Consider not committing them in
  the template at all (the workflow regenerates them).
- **`release-please` `release-type: simple`** does not bump `package.json`,
  `Cargo.toml` or `app.json`. A multi-app repo needs `extra-files` entries to
  keep versions in sync; the template could show an example.
- **Zizmor `cache-poisoning`** flags `actions/setup-node` with `cache: npm` in
  any workflow that publishes release artifacts. A note in `AGENTS.md` (use
  `package-manager-cache: false` in release workflows) would save time.
- **Windows story.** The README explains WSL2 well, but the no-flake path lists
  only Podman/Docker tooling. A native-app project needs different
  prerequisites (Rust, Tauri prerequisites, Android SDK), so a generic "install
  what your stack needs" paragraph would help.
- **No home for non-container toolchains.** Rust, a JDK and the Android SDK had
  no obvious place. A short "adding a language toolchain" section next to
  "adding a tool" (binary release vs nixpkgs, and the unfree Android SDK case)
  would help. The "never compile" rule is clear but does not say what to do
  when upstream publishes no binary and the nixpkgs build is large.
- **Nix flake and untracked files.** A new `nix/<tool>.nix` must be `git add`ed
  before `nix flake check` sees it. One line in the "add a tool" docs would
  prevent confusion.

## Small nits

- `README.md` first line is a comment about `adapt.py --rename`, and the badge
  points at a file that no longer exists after `--clean`; the badge shows
  nothing until the first Scorecard PR is merged. Say so near the badge.
- `.gitignore` carries Python and database-dump entries tied to template
  features; group them by feature so they are easy to drop.
- `justfile` `rebuild` and `nuke` are container-specific and sit among general
  recipes; module split (above) fixes this.
- The CONTRIBUTING troubleshooting example is Podman-specific; a generic or
  rotating example would suit non-container projects.

## Suggested priority

1. Layer or modularise the container stack (flake, justfile, CI, docs).
2. Make `adapt.py` remove its own residue and offer a "no containers" option.
3. Cover the leftover template wording in scripts and workflow messages.
4. Document multi-app and non-Node setups (`release-please` extra-files,
   language toolchains, matrix discovery).

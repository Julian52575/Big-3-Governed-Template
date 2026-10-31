# Adaptation reports

Feedback from projects created from this template. Each report says what
carried over, what got in the way and what would have helped. They drive
changes to the template, `adapt.py` and `README-ADAPT.md`.

## Writing a report

After you adapt the template to a project (or partway through, if you get
stuck):

1. Copy [`TEMPLATE.md`](TEMPLATE.md) to
   `<Project>-TEMPLATE-ADAPT-FEEDBACK.md`.
2. Fill in the sections and delete those that do not apply.
3. Open a pull request that adds the file here.

An AI agent that did the adaptation can write the report itself. Ask it to
"fill in `adapt-report/TEMPLATE.md` for this adaptation".

## What makes a report useful

- **Context first.** What the project ships and what was kept or dropped.
  A desktop app hits different problems than a container stack.
- **Name exact places**: files, `justfile` recipes, CI jobs, `adapt.py`
  flags. A table of files touched is the most useful part of a report.
- **Say what worked.** It tells maintainers what must not break.
- **Suggest a fix** where you can, and share workarounds you wrote (a
  workflow, a recipe) that could ship in the template.
- **Rank your suggestions** so the biggest time costs are fixed first.
- Facts only. Leave out secrets, private URLs and internal project details.

## Reports

| Report | Project | Shape |
| ------ | ------- | ----- |
| [DokKodi](DokKodi-TEMPLATE-ADAPT-FEEDBACK.md) | Tauri desktop app + Expo Android app | no containers |
| [Prompter](Prompter-TEMPLATE-ADAPT-FEEDBACK.md) | single-file local web app (Vite + Preact) | no backend, database or images |

## Recurring themes

Raised by more than one report, so fix these first:

- The demo container stack (Podman, Compose, Traefik, Postgres, Prisma, GHCR)
  is wired through many files. Removing it needs profiles or layers in
  `adapt.py`, or at least a per-component removal checklist.
- `AGENTS.md` and `adapt.py` remain after adaptation and still describe the
  template. A project-oriented `AGENTS.md` and a retire step are wanted.
- zizmor `cache-poisoning` on `actions/setup-node` with `cache: npm` in
  release workflows. Use `package-manager-cache: false`.
- Pinned Node.js in the dev shell (`nix/nodejs.nix`).

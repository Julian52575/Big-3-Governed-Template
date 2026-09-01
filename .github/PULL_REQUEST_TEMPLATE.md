<!--
  The PR title MUST follow Conventional Commits -- CI checks it.
    feat(api): add /users endpoint
    fix(web): stop double-submit on slow networks
  Read CONTRIBUTING.md before opening anything larger than a small fix.
-->

## What

<!-- The change in one or two sentences. What is different after this merges. -->

## Why

<!-- The problem being solved. Link the issue that motivates it. -->

Closes #

## How it was tested

<!-- Numbered, from a clean checkout. Someone else should be able to repeat this. -->

1. nix develop
2. just up -d
3. ...

## Screenshots / output

<!-- Anything visible in the UI or on the CLI. Delete this section if not applicable. -->

## Breaking changes

<!--
  Delete this section if there are none. Otherwise: what breaks, and the
  migration path for someone upgrading.
-->

## Checklist

- [ ] PR title is a valid Conventional Commit
- [ ] `nix flake check --no-build` passes locally
- [ ] `podman-compose -f docker-compose.yml config` still validates (if compose changed)
- [ ] Tests added or updated for the change
- [ ] Docs updated (README / comments / `.env.example`) if behaviour changed
- [ ] I reviewed my own diff

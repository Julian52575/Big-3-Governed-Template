# Troubleshoot

Known incidents with their cause and fix. Rules for adding entries are in
[CONTRIBUTING.md](../CONTRIBUTING.md#troubleshooting).

<!-- Example entry -- copy, then delete this comment:

## Podman "Not a directory" when starting the stack

**Error:** `just up` fails with `mount ... not a directory` on every container.

**Occurrences:** 2026-01-01 (WSL2, repo under /mnt/c).

**Cause:** the repo sits on a network/virtualised filesystem; overlay storage
needs POSIX semantics.

**Solution:** set `PODMAN_STORAGE_DIR` to a path on a local disk, or move the
repo into the Linux filesystem.
-->

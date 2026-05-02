# File Permissions

This document describes how `gemini-auth` manages file and directory permissions under `~/.gemini`.

## Directory permissions

On Unix-like systems, `gemini-auth` hardens this managed directory to `0700`:

- `<gemini_home>/accounts/`

It does not currently force `<gemini_home>/` itself to `0700`.

## Managed sensitive files

On Unix-like systems, `gemini-auth` creates these managed sensitive files with `0600` immediately and keeps them private on rewrite/sync paths:

- `<gemini_home>/accounts/registry.json`
- `<gemini_home>/accounts/<account file key>.auth.json`
- `<gemini_home>/accounts/auth.json.bak.YYYYMMDD-hhmmss[.N]`
- `<gemini_home>/accounts/registry.json.bak.YYYYMMDD-hhmmss[.N]`

Important details:

- Managed copy paths create the destination with `0600` at copy time instead of copying first and fixing the mode afterward.
- The atomic `registry.json` save path creates the replacement file with `0600` before the final rename.
- Lock files under `<gemini_home>/accounts/` are not secrets; they rely on the parent `0700` directory instead of extra per-file hardening.

## Live auth.json behavior

The live `<gemini_home>/auth.json` is intentionally treated differently from the managed files above.

On Unix-like systems:

- `gemini-auth login` leaves the live file at whatever mode the external `gemini login` flow produced.
- Foreground sync updates the managed snapshot under `accounts/` and does not re-harden the live `auth.json`.
- When a switch-style flow replaces an existing `<gemini_home>/auth.json`, it preserves that file's current mode instead of forcing `0600`.
- When `<gemini_home>/auth.json` is missing and must be recreated from a managed snapshot, the recreated file ends up private because the managed snapshot source is already `0600`.

## Windows behavior

On Windows, POSIX mode bits are skipped.

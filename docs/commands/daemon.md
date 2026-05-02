# `gemini-auth daemon`

## Usage

```shell
gemini-auth daemon --watch
gemini-auth daemon --once
```

## Behavior

`daemon` is the background worker entrypoint used by managed auto-switch services.

- `--watch` runs the long-lived watcher loop.
- `--once` runs one reconciliation pass and exits.
- Normal users should prefer `gemini-auth config auto enable` and `gemini-auth config auto disable`.

Runtime rules for the watcher live in [docs/auto-switch.md](../auto-switch.md).

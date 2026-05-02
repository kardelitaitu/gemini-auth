# `gemini-auth login`

## Usage

```shell
gemini-auth login
gemini-auth login --device-auth
```

## Behavior

- Runs `gemini login`, or `gemini login --device-auth` when requested.
- Reads the resulting `auth.json` from the active Gemini home.
- Adds or updates the current account in `registry.json`.
- Stores a managed account snapshot under `accounts/<account file key>.auth.json`.
- Makes the logged-in account active when import succeeds.

## Notes

- `gemini` must be available on `PATH`.
- Login-created accounts do not get an alias. Use `import <file> --alias <alias>` when an alias is needed.
- Invalid or incomplete auth files are rejected with the same auth validation rules used by `import`.

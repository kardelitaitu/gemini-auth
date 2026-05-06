# Gemini Auth [![latest release](https://img.shields.io/github/v/release/kardelitaitu/gemini-auth?sort=semver&label=latest)](https://github.com/kardelitaitu/gemini-auth/releases/latest) [![latest pre-release](https://img.shields.io/github/v/release/kardelitaitu/gemini-auth?include_prereleases&sort=semver&filter=*-*&label=pre-release)](https://github.com/kardelitaitu/gemini-auth/releases)

![command list](https://github.com/user-attachments/assets/6c13a2d6-f9da-47ea-8ec8-0394fc072d40)

`gemini-auth` is a command-line tool for switching Gemini accounts.

> [!IMPORTANT]
> For **Gemini CLI** and **Gemini App** users, switch accounts, then restart the client for the new account to take effect.
>
> If you use the CLI and want seamless automatic account switching without restarting, use the forked [`gemini`](https://github.com/kardelitaitu/gemini), an enhanced Gemini CLI. Install it with `npm i -g @kardelitaitu/gemini` and run `gemini`.

## Supported Platforms

`gemini-auth` works with these Gemini clients:

- Gemini CLI
- VS Code extension
- Gemini App

For the best experience, install the Gemini CLI even if you mainly use the VS Code extension or the App, because it makes adding accounts easier:

```shell
npm install -g @kardelitaitu/gemini
```

After that, you can use `gemini login`, `gemini login --device-auth`, `gemini-auth login`, or `gemini-auth login --device-auth` to sign in and add accounts more easily.

## Migration from codex-auth

If you're migrating from `codex-auth` to `gemini-auth`, see the [migration guide](MIGRATION.md) for detailed instructions on updating your workflow and data.

## Install

Install with npm:

```shell
npm install -g @kardelitaitu/gemini-auth
```

  You can also run it without a global install:

```shell
npx @kardelitaitu/gemini-auth list
```

  npm packages currently support Linux x64, Linux arm64, macOS x64, macOS arm64, Windows x64, and Windows arm64.

### Uninstall

#### npm

Remove the npm package:

```shell
npm uninstall -g @kardelitaitu/gemini-auth
```

## Commands

Detailed command documentation lives in [docs/commands/README.md](./docs/commands/README.md).

### Account Management

| Command | Description |
|---------|-------------|
| [`gemini-auth list [--live] [--api\|--skip-api]`](./docs/commands/list.md) | List stored accounts and usage state |
| [`gemini-auth login [--device-auth]`](./docs/commands/login.md) | Run `gemini login`, then add the current account |
| [`gemini-auth switch [--live] [--api\|--skip-api]`](./docs/commands/switch.md) | Switch the active account interactively |
| [`gemini-auth switch <query>`](./docs/commands/switch.md) | Switch directly by row number or account selector |
| [`gemini-auth remove [--live] [--api\|--skip-api]`](./docs/commands/remove.md) | Remove accounts interactively |
| [`gemini-auth remove <query> [<query>...]`](./docs/commands/remove.md) | Remove accounts by selector |
| [`gemini-auth remove --all`](./docs/commands/remove.md) | Remove all stored accounts |
| [`gemini-auth status`](./docs/commands/status.md) | Show auto-switch, service, and usage status |

### Import and Maintenance

| Command | Description |
|---------|-------------|
| [`gemini-auth import <path> [--alias <alias>]`](./docs/commands/import.md) | Import a single auth file or batch import a folder |
| [`gemini-auth import --cpa [<path>]`](./docs/commands/import.md) | Import CLIProxyAPI token JSON |
| [`gemini-auth import --purge [<path>]`](./docs/commands/import.md) | Rebuild `registry.json` from auth files |
| [`gemini-auth clean`](./docs/commands/clean.md) | Delete managed backup and stale account files |

### Configuration

| Command | Description |
|---------|-------------|
| [`gemini-auth config auto enable\|disable`](./docs/commands/config.md) | Enable or disable background auto-switching |
| [`gemini-auth config auto --5h <percent> [--weekly <percent>]`](./docs/commands/config.md) | Configure background auto-switch thresholds |
| [`gemini-auth config api enable\|disable`](./docs/commands/config.md) | Enable or disable default API-backed refresh |

## Quick Examples

```shell
gemini-auth list
gemini-auth switch
gemini-auth switch 02
gemini-auth remove work
gemini-auth import /path/to/auth.json --alias personal
gemini-auth config api disable
gemini-auth status
```

## Q&A

### Why is my usage limit not refreshing?

If `gemini-auth` is using local-only usage refresh, it reads the newest `~/.gemini/sessions/**/rollout-*.jsonl` file. Recent Gemini builds often write `token_count` events with `rate_limits: null`. The local files may still contain older usable usage limit data, but in practice they can lag by several hours, so local-only refresh may show a usage limit snapshot from hours ago instead of your latest state.

- Upstream Gemini issue: [kardelitaitu/gemini-auth#1](https://github.com/kardelitaitu/gemini-auth/issues/1)

You can switch usage limit refresh to the usage API with:

```shell
gemini-auth config api enable
```

Then confirm the current mode with:

```shell
gemini-auth status
```

`status` should show `usage: api`.

Verify with:

```shell
gemini exec "say hello"
```

## Disclaimer

This project is provided as-is and use is at your own risk.

**Usage Data Refresh Source:**
`gemini-auth` supports two sources for refreshing account usage/usage limit information:

1. **API (default):** When `config api enable` is on, the tool makes direct HTTPS requests to Gemini's endpoints using your account's access token. This enables both usage refresh and account name refresh. npm installs already satisfy the runtime requirement.

2. **Local-only:** When `config api disable` is on, the tool scans local `~/.gemini/sessions/*/rollout-*.jsonl` files for usage data and skips account name refresh API calls. This mode is safer, but it can be less accurate because recent Gemini rollout files often contain `rate_limits: null`, so the latest local usage limit data may lag by several hours.

**API Call Declaration:**
By enabling API(`gemini-auth config api enable`), this tool will send your Gemini access token to Google's servers, including `https://gemini.google.com/v1/usage` for usage limit and account information. This behavior may be detected by Google and could violate their terms of service, potentially leading to account suspension or other risks. The decision to use this feature and any resulting consequences are entirely yours.

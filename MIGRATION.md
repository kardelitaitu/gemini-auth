# Migration Guide: codex-auth → gemini-auth

This guide helps existing `codex-auth` users migrate to `gemini-auth` for Google Gemini CLI support.

## Overview

`gemini-auth` is a fork of `codex-auth` that has been adapted to work with Google Gemini CLI instead of OpenAI Codex. The core functionality and user experience remain the same, but the authentication system has been updated for Gemini's OAuth2 format.

## Key Changes

### ✅ What's the Same
- Command-line interface and usage patterns
- Account management and switching
- Registry storage and backup systems
- Configuration options and auto-switching
- All CLI commands work identically

### 🔄 What Changed
- **Authentication**: Now uses Google OAuth2 instead of OpenAI tokens
- **Directory**: `~/.codex/` → `~/.gemini/`
- **API**: Gemini API endpoints (when available)
- **Plans**: OpenAI plans (free/plus/team) → Gemini plans (free/pro/ultra)

### ❌ What's Not Available
- **Team accounts**: Gemini doesn't have team/workspace accounts like OpenAI
- **Usage tracking**: Gemini usage API not yet implemented
- **Codex-specific features**: Any OpenAI Codex specific functionality

## Migration Steps

### 1. Install gemini-auth

```bash
# Remove old codex-auth
npm uninstall -g codex-auth

# Install gemini-auth
npm install -g @kardelitaitu/gemini-auth
```

### 2. Migrate Account Data (Optional)

If you want to keep your existing account configurations:

```bash
# Backup your codex data
cp -r ~/.codex ~/.codex-backup

# The registry format is compatible, but you'll need to:
# 1. Re-import your Gemini auth tokens
# 2. Update any custom configurations
```

**Note**: Due to authentication format changes, you'll need to re-authenticate with Gemini. The old OpenAI tokens won't work.

### 3. Update Your Workflow

```bash
# Old commands (still work, but for Gemini)
codex-auth list          → gemini-auth list
codex-auth switch        → gemini-auth switch
codex-auth import        → gemini-auth import

# Authenticate with Gemini
gemini-auth login
# or with device auth
gemini-auth login --device-auth
```

### 4. Update Environment Variables

```bash
# Old
export CODEX_HOME=/path/to/custom/dir

# New
export GEMINI_HOME=/path/to/custom/dir
```

## Troubleshooting

### "MissingAlias" Error
The new version enforces that accounts have aliases. If you get this error:
1. Check your registry file: `~/.gemini/registry.json`
2. Ensure all accounts have non-empty aliases
3. Re-import accounts with proper aliases

### Authentication Issues
- Gemini uses different OAuth2 flow than OpenAI
- Make sure you're using a Gemini-compatible CLI
- Try `gemini-auth login --device-auth` if web login fails

### Directory Changes
- Old: `~/.codex/`
- New: `~/.gemini/`
- The tools don't share data, so you'll need to set up accounts again

## For Developers

### Code Changes
- Plan types: `OpenAI.PlanType` → `Gemini.PlanType`
- Auth parsing: OpenAI JWT → Google OAuth2
- API calls: OpenAI endpoints → Gemini endpoints (TBD)

### Testing
- Test fixtures updated for Gemini OAuth2 format
- Plan expectations updated (Business/Plus → Pro/Free)
- Registry paths updated for `.gemini/` directory

## Need Help?

- **Issues**: [GitHub Issues](https://github.com/kardelitaitu/gemini-auth/issues)
- **Documentation**: [README](https://github.com/kardelitaitu/gemini-auth#readme)
- **Gemini CLI**: Install the enhanced Gemini CLI: `npm i -g @kardelitaitu/gemini`

## Compatibility Matrix

| Feature | codex-auth | gemini-auth | Notes |
|---------|------------|-------------|-------|
| Account switching | ✅ | ✅ | Same commands |
| Auto-switching | ✅ | ✅ | Same configuration |
| Registry backup | ✅ | ✅ | Same format |
| CLI integration | ✅ | ✅ | Gemini CLI support |
| Team accounts | ✅ | ❌ | Gemini doesn't have teams |
| Usage tracking | ✅ | ⏳ | Gemini API not yet available |
| Token format | OpenAI | Google OAuth2 | Re-auth required |

---

**Migration completed successfully?** ⭐ Star the [gemini-auth repository](https://github.com/kardelitaitu/gemini-auth)!
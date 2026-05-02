# Gemini-CLI Auth Migration TODO

## Overview
Migrate `gemini-auth` tool from OpenAI Gemini CLI authentication to Google Gemini CLI authentication.

## Research Phase

- [x] Research Gemini CLI auth.json structure
  - **Location**: `~/.gemini/oauth_creds.json` (NOT auth.json)
  - **File name**: `oauth_creds.json`
  - **JSON schema**: Google OAuth2 tokens (flat structure)
  ```json
  {
    "access_token": "ya29.a0...",
    "scope": "https://www.googleapis.com/auth/...",
    "token_type": "Bearer",
    "id_token": "eyJ...",  // JWT with user info
    "expiry_date": 1777639046350,  // timestamp ms
    "refresh_token": "1//0gbq..."
  }
  ```
  - Key fields: `access_token`, `id_token` (JWT), `refresh_token`, `expiry_date`
  - JWT `id_token` contains: `email`, `name`, `picture`, `sub` (google_user_id)

- [x] Research Gemini CLI directory structure
  - **Default home path**: `~/.gemini/` (NOT `~/.codex/`)
  - **Environment variable**: `GEMINI_HOME` (verified)
  - **Account storage**: Single `oauth_creds.json` (multi-account TBD)

- [ ] Research Gemini API for usage/quota
  - Usage refresh endpoints (if any)
  - Quota/rate limit structure
  - Plan types: Free, Pro, Ultra, etc.

## Core Changes

### 1. Path & Environment Variables (`src/registry/common.zig`)
- [x] Change `CODEX_HOME` → `GEMINI_HOME` (done via script)
- [x] Change default home `~/.codex` → `~/.gemini` (done)
- [x] Update `resolveCodexHome()` → `resolveGeminiHome()` (done)
- [x] Update `resolveUserHome()` if needed (done)
- [x] Rename functions: `activeAuthPath()`, `accountAuthPath()`, etc. (done)

### 2. Auth JSON Parsing (`src/auth/auth.zig`)
- [x] Rewrite `parseAuthInfo()` for Gemini OAuth2 format (done)
  - Removed OpenAI JWT decoding logic (kept Google JWT for id_token)
  - Parse Google OAuth2 tokens (access_token, refresh_token, expiry_date)
  - Extract user email from Google id_token JWT
- [x] Update `AuthInfo` struct: (done)
  - Removed `chatgpt_account_id`, `chatgpt_user_id`
  - Added Gemini-specific fields (`google_user_id`, `name`)
  - Removed `auth_mode` (not needed for Gemini)
- [x] Rewrite `decodeJwtPayload()` - kept for Google id_token parsing
- [x] Removed `convertCpaAuthJson()` - not applicable for Gemini

### 3. Account Records (`src/registry/common.zig`)
- [x] Update `AccountRecord` struct for Gemini (done)
- [x] Update `PlanType` enum: OpenAI plans → Gemini plans (done)
  - Gemini: `free, pro, ultra, unknown`
- [x] Update `planLabel()` function (done)
- [x] Update `parsePlanType()` function (removed, not needed)

### 4. Registry & Storage (`src/registry/`)
- [x] Update `accountAuthPath()` - file naming convention (done)
- [x] Update `registryPath()` - `registry.json` location (done)
- [x] Update `ensureAccountsDir()` - `~/.gemini/accounts/` (done)
- [x] Update backup file naming: `oauth_creds.json.bak.*` (done)

### 5. API Integration (`src/api/`)
- [x] Replace OpenAI API calls with Gemini equivalents (simplified)
  - Removed OpenAI-specific API endpoints
  - Simplified `account_api.zig` - removed team account functions
  - Simplified `usage.zig` - removed OpenAI usage refresh logic
- [x] Update `account_api.zig` for Gemini API (simplified)
- [ ] Add TBD Gemini API endpoints when available

### 6. CLI Commands & UI (`src/cli/`, `src/tui/`)
- [x] Update all CLI output: "codex" → "gemini" (done via script)
- [x] Update binary name references (done)
- [x] Update help text and examples (done)
- [x] Update TUI labels and menus (done)

### 7. Import/Export (`src/registry/import*.zig`)
- [x] Update `importAuthFile()` for Gemini auth.json format (done)
- [x] Removed `importCpaPath()` - not applicable for Gemini
- [x] Update `autoImportActiveAuth()` for Gemini (done)

### 8. Tests (`tests/`)
- [x] Updated `tests/*.zig` with `gemini_auth` (done via script)
- [ ] Update test auth samples to Gemini OAuth2 format
- [ ] Update `tests/registry_test.zig` for new paths/structures
- [ ] Update `tests/cli_integration_test.zig` for Gemini CLI
- [ ] Create new test auth.json samples for Gemini format
- [ ] Verify all tests pass (when Zig available)

### 9. Documentation
- [x] Update `README.md`
  - Changed "Codex Auth" → "Gemini Auth" (done via script)
  - Update install instructions (npm package name) (pending)
  - Update CLI examples: `codex-auth` → `gemini-auth` (done)
  - Update supported platforms (pending)
- [ ] Update `docs/commands/*.md` for new CLI
- [x] Update `USER.md` if exists (done)
- [x] Update `AGENTS.md` if needed (done)

### 10. Build & Config
- [x] Update `build.zig` - binary name, paths (done)
- [x] Update `build.zig.zon` - package name, description (done)
- [x] Update `package.json` - npm package name, description, bin (done via script)
- [x] Update `AGENTS.md` instructions (done)

## Detailed Task Breakdown

### Task 4: Update API Module
Files: `src/api/*.zig`
- [x] Rewrite API calls for Gemini (simplified)
- [x] Update usage refresh logic (simplified)
- [x] Simplify `account_api.zig` - remove team accounts
- [ ] Add Gemini API endpoints when available

### Task 5: Update CLI
Files: `src/cli/*.zig`, `src/tui/*.zig`
- [x] Rename commands if needed (done)
- [x] Update all user-facing text (done)
- [x] Update error messages (done)

### Task 6: Update Tests
- [x] Replace all test fixtures with `gemini_auth` (done via script)
- [ ] Update test auth samples to Gemini OAuth2 format
- [ ] Update path assertions
- [ ] Update mock API responses
- [ ] Verify all tests pass (when Zig available)

### Task 7: Update Build & Package
- [x] Update build configuration (done)
- [x] Update npm package metadata (done)
- [ ] Test build process

### Task 8: Documentation
- [x] Rewrite README.md (partially done)
- [ ] Update command documentation
- [ ] Add migration notes if needed

## Verification Checklist

- [ ] `zig build test` passes
- [ ] `zig build run -- list` works with Gemini auth
- [ ] Import Gemini auth.json works
- [ ] Switch accounts works
- [ ] Remove accounts works
- [ ] Usage refresh works (if applicable)
- [ ] All CLI commands work with Gemini CLI
- [ ] npm package installs and runs correctly

## Notes

- Keep code structure similar for easier maintenance
- Gemini CLI may have different auth storage - verify before implementing
- Consider backward compatibility if needed
- Document any Gemini CLI limitations discovered

## Questions to Answer

1. What is the exact path for Gemini CLI auth.json?
   **Answer**: `~/.gemini/oauth_creds.json`
2. What does Gemini CLI auth.json look like (sample)?
   **Answer**: Provided - Google OAuth2 format with id_token JWT
3. Does Gemini CLI support multiple accounts?
   **Answer**: TBD - currently single `oauth_creds.json`
4. What environment variable controls Gemini home directory?
   **Answer**: `GEMINI_HOME` (implemented)
5. Does Gemini have usage/quota API similar to OpenAI?
   **Answer**: TBD
6. What plan types does Gemini CLI support?
   **Answer**: Free, Pro, Ultra (implemented)

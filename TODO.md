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
  - **Default home path**: `~/.gemini/` (NOT `~/.gemini/`)
  - **Environment variable**: Need to verify `GEMINI_HOME` support
  - **Account storage**: Single `oauth_creds.json` (multi-account TBD)

- [ ] Research Gemini API for usage/quota
  - Usage refresh endpoints (if any)
  - Quota/rate limit structure
  - Plan types: Free, Pro, Ultra, etc.

## Core Changes

### 1. Path & Environment Variables (`src/registry/common.zig`)
- [ ] Change `GEMINI_HOME` → `GEMINI_HOME`
- [ ] Change default home `~/.gemini` → `~/.gemini`
- [ ] Update `resolveGeminiHome()` → `resolveGeminiHome()`
- [ ] Update `resolveUserHome()` if needed
- [ ] Rename functions: `activeAuthPath()`, `accountAuthPath()`, etc.

### 2. Auth JSON Parsing (`src/auth/auth.zig`)
- [ ] Rewrite `parseAuthInfo()` for Gemini OAuth2 format
  - Remove OpenAI JWT decoding logic
  - Parse Google OAuth2 tokens (access_token, refresh_token, expires_in)
  - Extract user email from Google userinfo endpoint or token
- [ ] Update `AuthInfo` struct:
  - Remove `chatgpt_account_id`, `chatgpt_user_id`
  - Add Gemini-specific fields (google_user_id, etc.)
  - Update `auth_mode` enum: `chatgpt` → `gemini`
- [ ] Rewrite `decodeJwtPayload()` or remove if not needed
- [ ] Update `convertCpaAuthJson()` or remove if not applicable

### 3. Account Records (`src/registry/common.zig`)
- [ ] Update `AccountRecord` struct for Gemini
- [ ] Update `PlanType` enum: OpenAI plans → Gemini plans
  - Current: `free, plus, prolite, pro, team, business, enterprise, edu`
  - Gemini: `free, pro, ultra, unknown`
- [ ] Update `planLabel()` function
- [ ] Update `parsePlanType()` function

### 4. Registry & Storage (`src/registry/`)
- [ ] Update `accountAuthPath()` - file naming convention
- [ ] Update `registryPath()` - `registry.json` location
- [ ] Update `ensureAccountsDir()` - `~/.gemini/accounts/`
- [ ] Update backup file naming if needed

### 5. API Integration (`src/api/`)
- [ ] Replace OpenAI API calls with Gemini equivalents
  - Usage refresh: OpenAI `/backend-api/wham/usage` → Gemini equivalent
  - Account name: OpenAI `/backend-api/accounts/check/v4-2023-04-27` → Google endpoint
- [ ] Update `account_api.zig` for Gemini API

### 6. CLI Commands & UI (`src/cli/`, `src/tui/`)
- [ ] Update all CLI output: "gemini" → "gemini"
- [ ] Update binary name references
- [ ] Update help text and examples
- [ ] Update TUI labels and menus

### 7. Import/Export (`src/registry/import*.zig`)
- [ ] Update `importAuthFile()` for Gemini auth.json format
- [ ] Update `importCpaPath()` or remove if not applicable
- [ ] Update `autoImportActiveAuth()` for Gemini

### 8. Tests (`tests/`)
- [ ] Update `tests/auth_test.zig` with Gemini auth samples
- [ ] Update `tests/registry_test.zig` for new paths/structures
- [ ] Update `tests/cli_integration_test.zig` for Gemini CLI
- [ ] Update `tests/workflows_core_test.zig`
- [ ] Create new test auth.json samples for Gemini format

### 9. Documentation
- [ ] Update `README.md`
  - Change "Gemini Auth" → "Gemini Auth"
  - Update install instructions (npm package name)
  - Update CLI examples: `gemini-auth` → `gemini-auth`
  - Update supported platforms
- [ ] Update `docs/commands/*.md` for new CLI
- [ ] Update `USER.md` if exists
- [ ] Update `AGENTS.md` if needed

### 10. Build & Config
- [ ] Update `build.zig` - binary name, paths
- [ ] Update `build.zig.zon` - package name, description
- [ ] Update `package.json` - npm package name, description, bin
- [ ] Update `AGENTS.md` instructions

## Detailed Task Breakdown

### Task 1: Create Gemini Auth Sample
- [ ] Obtain sample Gemini CLI auth.json
- [ ] Document the exact JSON structure
- [ ] Identify all required fields
- [ ] Note any differences from OpenAI format

### Task 2: Update Core Auth Module
Files: `src/auth/auth.zig`, `src/auth/account.zig`
- [ ] Modify `AuthInfo` struct
- [ ] Rewrite `parseAuthInfo()` 
- [ ] Remove OpenAI-specific JWT parsing
- [ ] Add Gemini token parsing
- [ ] Update `AuthMode` enum

### Task 3: Update Registry Module
Files: `src/registry/common.zig`, `src/registry/root.zig`
- [ ] Update all path functions
- [ ] Update `resolveGeminiHome()`
- [ ] Update `AccountRecord` for Gemini
- [ ] Update `PlanType` enum

### Task 4: Update API Module
Files: `src/api/*.zig`
- [ ] Rewrite API calls for Gemini
- [ ] Update usage refresh logic
- [ ] Update account name refresh

### Task 5: Update CLI
Files: `src/cli/*.zig`, `src/tui/*.zig`
- [ ] Rename commands if needed
- [ ] Update all user-facing text
- [ ] Update error messages

### Task 6: Update Tests
- [ ] Replace all test fixtures with Gemini format
- [ ] Update path assertions
- [ ] Update mock API responses
- [ ] Verify all tests pass

### Task 7: Update Build & Package
- [ ] Update build configuration
- [ ] Update npm package metadata
- [ ] Test build process

### Task 8: Documentation
- [ ] Rewrite README.md
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
2. What does Gemini CLI auth.json look like (sample)?
3. Does Gemini CLI support multiple accounts?
4. What environment variable controls Gemini home directory?
5. Does Gemini have usage/quota API similar to OpenAI?
6. What plan types does Gemini CLI support?

const std = @import("std");
const app_runtime = @import("../core/runtime.zig");
const auth = @import("../auth/auth.zig");
const registry = @import("../registry/root.zig");
const account_api = @import("../api/account.zig");
const account_name_refresh = @import("../auth/account.zig");
const logging = @import("../auto/logging.zig");
const cli = @import("../cli/root.zig");

const emitDaemonLog = logging.emitDaemonLog;
const fieldSeparator = logging.fieldSeparator;

pub const AccountFetchFn = *const fn (
    allocator: std.mem.Allocator,
    access_token: []const u8,
) anyerror!?account_api.AccountEntry;

pub fn loadActiveAuthInfo(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
) !?auth.AuthInfo {
    const auth_path = try registry.activeAuthPath(allocator, gemini_home);
    defer allocator.free(auth_path);

    return auth.parseAuthInfo(allocator, auth_path) catch return null;
}

pub fn loadSingleFileImportAuthInfo(
    allocator: std.mem.Allocator,
    opts: cli.types.ImportOptions,
) !?auth.AuthInfo {
    if (opts.auth_path == null) return null;
    return auth.parseAuthInfo(allocator, opts.auth_path.?) catch return null;
}

pub fn shouldRefreshTeamAccountNamesForUserScopeWithAccountApiEnabled(
    reg: *registry.Registry,
    account_api_enabled: bool,
) bool {
    _ = reg;
    _ = account_api_enabled;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

pub fn shouldRefreshTeamAccountNamesForUser(
    reg: *registry.Registry,
    google_user_id: []const u8,
) bool {
    _ = reg;
    _ = google_user_id;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

pub const defaultAccountFetcher = account_api.fetchAccounts;

pub fn collectCandidates(
    allocator: std.mem.Allocator,
    reg: *registry.Registry,
) !std.ArrayList(account_name_refresh.Candidate) {
    _ = reg;
    var candidates = std.ArrayList(account_name_refresh.Candidate).empty;
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }

    // Gemini doesn't have team accounts like OpenAI
    // Return empty list
    return candidates;
}

pub fn maybeRefreshForegroundAccountNames(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    target: cli.types.Command,
    fetcher: AccountFetchFn,
) !bool {
    _ = allocator;
    _ = gemini_home;
    _ = reg;
    _ = target;
    _ = fetcher;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

pub fn refreshAccountNamesAfterLogin(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    fetcher: AccountFetchFn,
) !bool {
    _ = allocator;
    _ = gemini_home;
    _ = reg;
    _ = fetcher;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

pub fn refreshAccountNamesAfterSwitch(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    fetcher: AccountFetchFn,
) !bool {
    _ = allocator;
    _ = gemini_home;
    _ = reg;
    _ = fetcher;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

pub fn refreshAccountNamesAfterImport(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    fetcher: AccountFetchFn,
) !bool {
    _ = allocator;
    _ = gemini_home;
    _ = reg;
    _ = fetcher;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

pub fn shouldScheduleBackgroundAccountNameRefresh(
    reg: *registry.Registry,
    target: anytype,
) bool {
    _ = reg;
    _ = target;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

pub fn refreshAccountNamesForList(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    fetcher: AccountFetchFn,
) !bool {
    _ = allocator;
    _ = gemini_home;
    _ = reg;
    _ = fetcher;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

pub fn applyAccountNamesForUser(
    allocator: std.mem.Allocator,
    reg: *registry.Registry,
    google_user_id: []const u8,
    entries: []const account_api.AccountEntry,
) !bool {
    _ = allocator;
    _ = reg;
    _ = google_user_id;
    _ = entries;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

pub fn runBackgroundAccountNameRefresh(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    fetcher: AccountFetchFn,
) !void {
    _ = allocator;
    _ = gemini_home;
    _ = fetcher;
    // Gemini doesn't have team accounts like OpenAI
}

pub fn runBackgroundAccountNameRefreshWithLockAcquirer(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    fetcher: AccountFetchFn,
    lock_acquirer: anytype,
) !void {
    _ = allocator;
    _ = gemini_home;
    _ = fetcher;
    _ = lock_acquirer;
    // Gemini doesn't have team accounts like OpenAI
}

pub fn maybeRefreshForegroundAccountNamesWithAccountApiEnabled(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    target: anytype,
    fetcher: AccountFetchFn,
    account_api_enabled: bool,
) !bool {
    _ = allocator;
    _ = gemini_home;
    _ = reg;
    _ = target;
    _ = fetcher;
    _ = account_api_enabled;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

pub fn maybeRefreshForegroundAccountNamesWithAccountApiEnabledAndPersist(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    target: anytype,
    fetcher: AccountFetchFn,
    account_api_enabled: bool,
    persist: bool,
) !bool {
    _ = allocator;
    _ = gemini_home;
    _ = reg;
    _ = target;
    _ = fetcher;
    _ = account_api_enabled;
    _ = persist;
    // Gemini doesn't have team accounts like OpenAI
    return false;
}

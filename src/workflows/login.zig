const std = @import("std");
const cli = @import("../cli/root.zig");
const registry = @import("../registry/root.zig");
const auth = @import("../auth/auth.zig");
const account_names = @import("account_names.zig");

const defaultAccountFetcher = account_names.defaultAccountFetcher;
const refreshAccountNamesAfterLogin = account_names.refreshAccountNamesAfterLogin;

pub fn handleLogin(allocator: std.mem.Allocator, gemini_home: []const u8, opts: cli.types.LoginOptions) !void {
    cli.login.runGeminiLogin(opts) catch |err| switch (err) {
        error.GeminiLoginNotImplemented => {
            // Instructions provided, user needs to manually authenticate
            return;
        },
        else => return err,
    };

    const auth_path = try registry.activeAuthPath(allocator, gemini_home);
    defer allocator.free(auth_path);

    const info = try auth.parseAuthInfo(allocator, auth_path);
    defer info.deinit(allocator);

    var reg = try registry.loadRegistry(allocator, gemini_home);
    defer reg.deinit(allocator);

    const google_user_id = info.google_user_id orelse return error.MissingGoogleUserId;

    // For Gemini, create record key from google_user_id
    const record_key = try allocator.dupe(u8, google_user_id);
    defer allocator.free(record_key);
    const dest = try registry.accountAuthPath(allocator, gemini_home, record_key);
    defer allocator.free(dest);

    try registry.ensureAccountsDir(allocator, gemini_home);
    try registry.copyManagedFile(auth_path, dest);

    const record = try registry.accountFromAuth(allocator, "", &info);
    try registry.upsertAccount(allocator, &reg, record);
    try registry.setActiveAccountKey(allocator, &reg, record_key);
    _ = try refreshAccountNamesAfterLogin(allocator, gemini_home, &reg, defaultAccountFetcher);
    try registry.saveRegistry(allocator, gemini_home, &reg);
}

const std = @import("std");
const app_runtime = @import("../core/runtime.zig");
const account_api = @import("../api/account.zig");
const common = @import("common.zig");
const clean = @import("clean.zig");

const PlanType = common.PlanType;
const RateLimitWindow = common.RateLimitWindow;
const RateLimitSnapshot = common.RateLimitSnapshot;
const Registry = common.Registry;
const AccountRecord = common.AccountRecord;
const activeAuthPath = common.activeAuthPath;
const accountAuthPath = common.accountAuthPath;
const ensureAccountsDir = common.ensureAccountsDir;
const copyManagedFile = common.copyManagedFile;
const hardenSensitiveFile = common.hardenSensitiveFile;
const replaceFilePreservingPermissions = common.replaceFilePreservingPermissions;
const freeAccountRecord = common.freeAccountRecord;
const freeRateLimitSnapshot = common.freeRateLimitSnapshot;
const replaceOptionalStringAlloc = common.replaceOptionalStringAlloc;
const cloneOptionalStringAlloc = common.cloneOptionalStringAlloc;
const resolvePlan = common.resolvePlan;
const readFileIfExists = clean.readFileIfExists;
const fileEqualsBytes = clean.fileEqualsBytes;
const backupDir = clean.backupDir;
const backupAuthIfChanged = clean.backupAuthIfChanged;
const resolveStrictAccountAuthPath = clean.resolveStrictAccountAuthPath;

pub fn findAccountIndexByAccountKey(reg: *Registry, account_key: []const u8) ?usize {
    for (reg.accounts.items, 0..) |rec, i| {
        if (std.mem.eql(u8, rec.account_key, account_key)) return i;
    }
    return null;
}

pub fn setActiveAccountKey(allocator: std.mem.Allocator, reg: *Registry, account_key: []const u8) !void {
    if (reg.active_account_key) |k| {
        if (std.mem.eql(u8, k, account_key)) return;
    }
    const new_active_account_key = try allocator.dupe(u8, account_key);
    if (reg.active_account_key) |k| {
        allocator.free(k);
    }
    reg.active_account_key = new_active_account_key;
    reg.active_account_activated_at_ms = std.Io.Timestamp.now(app_runtime.io(), .real).toMilliseconds();
    const now = std.Io.Timestamp.now(app_runtime.io(), .real).toSeconds();
    for (reg.accounts.items) |*rec| {
        if (std.mem.eql(u8, rec.account_key, account_key)) {
            rec.last_used_at = now;
            break;
        }
    }
}

pub fn updateUsage(allocator: std.mem.Allocator, reg: *Registry, account_key: []const u8, snapshot: RateLimitSnapshot) void {
    const now = std.Io.Timestamp.now(app_runtime.io(), .real).toSeconds();
    for (reg.accounts.items) |*rec| {
        if (std.mem.eql(u8, rec.account_key, account_key)) {
            if (rec.last_usage) |*u| {
                if (u.credits) |*c| {
                    if (c.balance) |b| allocator.free(b);
                }
            }
            rec.last_usage = snapshot;
            rec.last_usage_at = now;
            break;
        }
    }
}

pub fn syncActiveAccountFromAuthWithImporter(allocator: std.mem.Allocator, gemini_home: []const u8, reg: *Registry, auto_importer: anytype) !bool {
    if (reg.accounts.items.len == 0) {
        return try auto_importer(allocator, gemini_home, reg);
    }

    const auth_path = try activeAuthPath(allocator, gemini_home);
    defer allocator.free(auth_path);

    const auth_bytes_opt = try readFileIfExists(allocator, auth_path);
    if (auth_bytes_opt == null) return false;
    const auth_bytes = auth_bytes_opt.?;
    defer allocator.free(auth_bytes);

    const info = @import("../auth/auth.zig").parseAuthInfo(allocator, auth_path) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => {
            std.log.warn("oauth_creds.json sync skipped: {s}", .{@errorName(err)});
            return false;
        },
    };
    defer info.deinit(allocator);

    const email = info.email orelse {
        std.log.warn("oauth_creds.json missing email; skipping sync", .{});
        return false;
    };
    const google_user_id = info.google_user_id orelse {
        std.log.warn("oauth_creds.json missing google_user_id; skipping sync", .{});
        return false;
    };

    const matched_index = findAccountIndexByAccountKey(reg, google_user_id);
    if (matched_index == null) {
        const dest = try accountAuthPath(allocator, gemini_home, google_user_id);
        defer allocator.free(dest);

        try ensureAccountsDir(allocator, gemini_home);
        try copyManagedFile(auth_path, dest);

        var record = try accountFromAuth(allocator, "", &info);
        var record_owned = true;
        errdefer if (record_owned) freeAccountRecord(allocator, &record);
        try upsertAccount(allocator, reg, record);
        record_owned = false;
        try setActiveAccountKey(allocator, reg, google_user_id);
        return true;
    }

    const idx = matched_index.?;
    const rec_account_key = reg.accounts.items[idx].account_key;
    var changed = false;
    if (reg.active_account_key) |k| {
        if (!std.mem.eql(u8, k, rec_account_key)) changed = true;
    } else {
        changed = true;
    }

    if (!std.mem.eql(u8, reg.accounts.items[idx].email, email)) {
        const new_email = try allocator.dupe(u8, email);
        allocator.free(reg.accounts.items[idx].email);
        reg.accounts.items[idx].email = new_email;
        changed = true;
    }

    const dest = try accountAuthPath(allocator, gemini_home, rec_account_key);
    defer allocator.free(dest);
    if (!(try fileEqualsBytes(allocator, dest, auth_bytes))) {
        try copyManagedFile(auth_path, dest);
        changed = true;
    } else {
        try hardenSensitiveFile(dest);
    }

    try setActiveAccountKey(allocator, reg, rec_account_key);
    return changed;
}

pub fn removeAccounts(allocator: std.mem.Allocator, gemini_home: []const u8, reg: *Registry, indices: []const usize) !void {
    if (indices.len == 0 or reg.accounts.items.len == 0) return;

    var removed = try allocator.alloc(bool, reg.accounts.items.len);
    defer allocator.free(removed);
    @memset(removed, false);
    for (indices) |idx| {
        if (idx < removed.len) removed[idx] = true;
    }

    try deleteRemovedAccountBackups(allocator, gemini_home, reg, removed);

    if (reg.active_account_key) |key| {
        var active_removed = false;
        for (reg.accounts.items, 0..) |rec, i| {
            if (removed[i] and std.mem.eql(u8, rec.account_key, key)) {
                active_removed = true;
                break;
            }
        }
        if (active_removed) {
            allocator.free(key);
            reg.active_account_key = null;
            reg.active_account_activated_at_ms = null;
        }
    }

    var write_idx: usize = 0;
    for (reg.accounts.items, 0..) |*rec, i| {
        if (removed[i]) {
            const preferred_path = try accountAuthPath(allocator, gemini_home, rec.account_key);
            defer allocator.free(preferred_path);
            std.Io.Dir.cwd().deleteFile(app_runtime.io(), preferred_path) catch {};
            freeAccountRecord(allocator, rec);
            continue;
        }
        if (write_idx != i) {
            reg.accounts.items[write_idx] = rec.*;
        }
        write_idx += 1;
    }
    reg.accounts.items.len = write_idx;
}

pub fn deleteRemovedAccountBackups(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *const Registry,
    removed: []const bool,
) !void {
    const dir_path = try backupDir(allocator, gemini_home);
    defer allocator.free(dir_path);

    var dir = std.Io.Dir.cwd().openDir(app_runtime.io(), dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer dir.close(app_runtime.io());

    var it = dir.iterate();
    while (try it.next(app_runtime.io())) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (!std.mem.startsWith(u8, entry.name, "oauth_creds.json.bak.")) continue;

        const path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        defer allocator.free(path);

        var info = @import("../auth/auth.zig").parseAuthInfo(allocator, path) catch continue;
        defer info.deinit(allocator);

        const google_user_id = info.google_user_id orelse continue;
        if (!isRemovedAccountKey(reg, removed, google_user_id)) continue;

        dir.deleteFile(app_runtime.io(), entry.name) catch {};
    }
}

pub fn isRemovedAccountKey(reg: *const Registry, removed: []const bool, record_key: []const u8) bool {
    for (reg.accounts.items, 0..) |rec, i| {
        if (!removed[i]) continue;
        if (std.mem.eql(u8, rec.account_key, record_key)) return true;
    }
    return false;
}

pub fn selectBestAccountIndexByUsage(reg: *Registry) ?usize {
    if (reg.accounts.items.len == 0) return null;
    const now = std.Io.Timestamp.now(app_runtime.io(), .real).toSeconds();
    var best_idx: ?usize = null;
    var best_score: i64 = -2;
    var best_seen: i64 = -1;
    for (reg.accounts.items, 0..) |rec, i| {
        const score = usageScoreAt(rec.last_usage, now) orelse -1;
        const seen = rec.last_usage_at orelse -1;
        if (score > best_score) {
            best_score = score;
            best_seen = seen;
            best_idx = i;
        } else if (score == best_score and seen > best_seen) {
            best_seen = seen;
            best_idx = i;
        }
    }
    return best_idx;
}

pub fn usageScoreAt(usage: ?RateLimitSnapshot, now: i64) ?i64 {
    const rate_5h = resolveRateWindow(usage, 300, true);
    const rate_week = resolveRateWindow(usage, 10080, false);
    const rem_5h = remainingPercentAt(rate_5h, now);
    const rem_week = remainingPercentAt(rate_week, now);
    if (rem_5h != null and rem_week != null) return @min(rem_5h.?, rem_week.?);
    if (rem_5h != null) return rem_5h.?;
    if (rem_week != null) return rem_week.?;
    return null;
}

pub fn remainingPercentAt(window: ?RateLimitWindow, now: i64) ?i64 {
    if (window == null) return null;
    if (window.?.resets_at) |resets_at| {
        if (resets_at <= now) return 100;
    }
    const remaining = 100.0 - window.?.used_percent;
    if (remaining <= 0.0) return 0;
    if (remaining >= 100.0) return 100;
    return @as(i64, @intFromFloat(remaining));
}

pub fn resolveRateWindow(usage: ?RateLimitSnapshot, minutes: i64, fallback_primary: bool) ?RateLimitWindow {
    if (usage == null) return null;
    if (usage.?.primary) |p| {
        if (p.window_minutes != null and p.window_minutes.? == minutes) return p;
    }
    if (usage.?.secondary) |s| {
        if (s.window_minutes != null and s.window_minutes.? == minutes) return s;
    }
    return if (fallback_primary) usage.?.primary else usage.?.secondary;
}

pub fn hasStoredAccountName(rec: *const AccountRecord) bool {
    const account_name = rec.account_name orelse return false;
    return account_name.len != 0;
}

pub fn isTeamAccount(rec: *const AccountRecord) bool {
    const plan = resolvePlan(rec) orelse return false;
    return plan == .team;
}

pub fn inAccountNameRefreshScope(reg: *const Registry, google_user_id: []const u8, rec: *const AccountRecord) bool {
    _ = reg;
    return std.mem.eql(u8, rec.google_user_id, google_user_id);
}

pub fn hasMissingAccountNameForUser(reg: *const Registry, google_user_id: []const u8) bool {
    for (reg.accounts.items) |rec| {
        if (!inAccountNameRefreshScope(reg, google_user_id, &rec)) continue;
        return false; // Simplified for Gemini - no team accounts
    }
    return false;
}

pub fn shouldFetchTeamAccountNamesForUser(reg: *const Registry, google_user_id: []const u8) bool {
    _ = reg;
    _ = google_user_id;
    return false; // Gemini doesn't have team accounts like Gemini
}

pub fn activeGoogleUserId(reg: *Registry) ?[]const u8 {
    const active_account_key = reg.active_account_key orelse return null;
    const idx = findAccountIndexByAccountKey(reg, active_account_key) orelse return null;
    return reg.accounts.items[idx].google_user_id;
}

pub fn applyAccountNamesForUser(
    allocator: std.mem.Allocator,
    reg: *Registry,
    google_user_id: []const u8,
    entries: []const account_api.AccountEntry,
) !bool {
    _ = allocator;
    _ = entries;
    const changed = false;
    for (reg.accounts.items) |*rec| {
        if (!inAccountNameRefreshScope(reg, google_user_id, rec)) continue;
        // Simplified for Gemini - no account_name refresh needed
        break;
    }
    return changed;
}

pub fn activateAccountByKey(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *Registry,
    account_key: []const u8,
) !void {
    _ = findAccountIndexByAccountKey(reg, account_key) orelse return error.AccountNotFound;
    const src = try resolveStrictAccountAuthPath(allocator, gemini_home, account_key);
    defer allocator.free(src);

    const dest = try activeAuthPath(allocator, gemini_home);
    defer allocator.free(dest);

    try backupAuthIfChanged(allocator, gemini_home, dest, src);
    try replaceFilePreservingPermissions(src, dest);
    try setActiveAccountKey(allocator, reg, account_key);
}

pub fn replaceActiveAuthWithAccountByKey(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *Registry,
    account_key: []const u8,
) !void {
    _ = findAccountIndexByAccountKey(reg, account_key) orelse return error.AccountNotFound;
    const src = try resolveStrictAccountAuthPath(allocator, gemini_home, account_key);
    defer allocator.free(src);

    const dest = try activeAuthPath(allocator, gemini_home);
    defer allocator.free(dest);

    try ensureAccountsDir(allocator, gemini_home);
    try replaceFilePreservingPermissions(src, dest);
    try setActiveAccountKey(allocator, reg, account_key);
}

pub fn accountFromAuth(
    allocator: std.mem.Allocator,
    alias: []const u8,
    info: *const @import("../auth/auth.zig").AuthInfo,
) !AccountRecord {
    const email = info.email orelse return error.MissingEmail;
    const google_user_id = info.google_user_id orelse return error.MissingGoogleUserId;
    const owned_google_user_id = try allocator.dupe(u8, google_user_id);
    errdefer allocator.free(owned_google_user_id);
    const owned_email = try allocator.dupe(u8, email);
    errdefer allocator.free(owned_email);
    const owned_alias = try allocator.dupe(u8, alias);
    errdefer allocator.free(owned_alias);

    var owned_name: ?[]u8 = null;
    errdefer if (owned_name) |n| allocator.free(n);
    if (info.name) |n| {
        owned_name = try allocator.dupe(u8, n);
    }

    return AccountRecord{
        .account_key = try allocator.dupe(u8, google_user_id),
        .google_user_id = owned_google_user_id,
        .email = owned_email,
        .alias = owned_alias,
        .name = owned_name,
        .account_name = null,
        .plan = null, // Gemini doesn't expose plan in auth token
        .created_at = std.Io.Timestamp.now(app_runtime.io(), .real).toSeconds(),
        .last_used_at = null,
        .last_usage = null,
        .last_usage_at = null,
        .last_local_rollout = null,
    };
}

pub fn recordFreshness(rec: *const AccountRecord) i64 {
    var best = rec.created_at;
    if (rec.last_used_at) |t| {
        if (t > best) best = t;
    }
    if (rec.last_usage_at) |t| {
        if (t > best) best = t;
    }
    return best;
}

pub fn mergeAccountRecord(allocator: std.mem.Allocator, dest: *AccountRecord, incoming: AccountRecord) void {
    var merged_incoming = incoming;
    if (recordFreshness(&merged_incoming) > recordFreshness(dest)) {
        if (merged_incoming.name == null and dest.name != null) {
            merged_incoming.name = cloneOptionalStringAlloc(allocator, dest.name) catch unreachable;
        }
        freeAccountRecord(allocator, dest);
        dest.* = merged_incoming;
        return;
    }
    if (merged_incoming.alias.len != 0 and dest.alias.len == 0) {
        const replacement = allocator.dupe(u8, merged_incoming.alias) catch allocator.dupe(u8, "") catch unreachable;
        allocator.free(dest.alias);
        dest.alias = replacement;
    }
    if (dest.name == null and merged_incoming.name != null) {
        dest.name = cloneOptionalStringAlloc(allocator, merged_incoming.name) catch unreachable;
    }
    freeAccountRecord(allocator, &merged_incoming);
}

pub fn upsertAccount(allocator: std.mem.Allocator, reg: *Registry, record: AccountRecord) !void {
    for (reg.accounts.items) |*rec| {
        if (std.mem.eql(u8, rec.account_key, record.account_key)) {
            mergeAccountRecord(allocator, rec, record);
            return;
        }
    }
    try reg.accounts.append(allocator, record);
}

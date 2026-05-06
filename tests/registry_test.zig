const std = @import("std");
const builtin = @import("builtin");
const fs = @import("gemini_auth").core.compat_fs;
const app_runtime = @import("gemini_auth").core.runtime;
const account_api = @import("gemini_auth").api.account;
const registry = @import("gemini_auth").registry;
const fixtures = @import("support/fixtures.zig");

fn makeEmptyRegistry() registry.Registry {
    return .{
        .schema_version = registry.current_schema_version,
        .active_account_key = null,
        .active_account_activated_at_ms = null,
        .auto_switch = registry.defaultAutoSwitchConfig(),
        .api = registry.defaultApiConfig(),
        .live = registry.defaultLiveConfig(),
        .accounts = std.ArrayList(registry.AccountRecord).empty,
    };
}

fn makeAccountRecord(
    allocator: std.mem.Allocator,
    email: []const u8,
    alias: []const u8,
    plan: ?registry.PlanType,
    created_at: i64,
) !registry.AccountRecord {
    // For Gemini, use email-derived google_user_id
    const google_user_id = try allocator.dupe(u8, email); // Simplified - in reality this would be the Google user ID
    errdefer allocator.free(google_user_id);

    return .{
        .account_key = try allocator.dupe(u8, google_user_id),
        .google_user_id = try allocator.dupe(u8, google_user_id),
        .email = try allocator.dupe(u8, email),
        .alias = try allocator.dupe(u8, alias),
        .name = null,
        .account_name = null,
        .plan = plan,
        .created_at = created_at,
        .last_used_at = null,
        .last_usage = null,
        .last_usage_at = null,
        .last_local_rollout = null,
    };
}

fn setRecordIds(
    allocator: std.mem.Allocator,
    rec: *registry.AccountRecord,
    google_user_id: []const u8,
) !void {
    allocator.free(rec.google_user_id);
    rec.google_user_id = try gpa.dupe(u8, google_user_id);
    allocator.free(rec.account_key);
    rec.account_key = try gpa.dupe(u8, google_user_id);
}

test "resolveGeminiHomeFromEnv prefers GEMINI_HOME over HOME" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("custom-gemini");
    const custom_gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner.inner, "custom-gemini");
    defer gpa.free(custom_gemini_home);

    const resolved = try registry.resolveGeminiHomeFromEnv(
        gpa,
        custom_gemini_home,
        "/tmp/home-root",
        null,
    );
    defer gpa.free(resolved);

    try std.testing.expectEqualStrings(custom_gemini_home, resolved);
}

test "resolveGeminiHomeFromEnv rejects a missing GEMINI_HOME override" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const missing = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(missing);
    const missing_path = try fs.path.join(gpa, &[_][]const u8{ missing, "missing-gemini-home" });
    defer gpa.free(missing_path);

    try std.testing.expectError(
        error.FileNotFound,
        registry.resolveGeminiHomeFromEnv(gpa, missing_path, "/tmp/home-root", null),
    );
}

test "resolveGeminiHomeFromEnv rejects a file GEMINI_HOME override" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "gemini-home.txt", .data = "not a directory" });
    const file_path = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, "gemini-home.txt");
    defer gpa.free(file_path);

    try std.testing.expectError(
        error.NotDir,
        registry.resolveGeminiHomeFromEnv(gpa, file_path, "/tmp/home-root", null),
    );
}

test "resolveGeminiHomeFromEnv falls back to HOME when GEMINI_HOME is empty" {
    const gpa = std.testing.allocator;

    const resolved = try registry.resolveGeminiHomeFromEnv(
        gpa,
        "",
        "/tmp/home-root",
        null,
    );
    defer gpa.free(resolved);

    const expected = try fs.path.join(gpa, &[_][]const u8{ "/tmp/home-root", ".gemini" });
    defer gpa.free(expected);

    try std.testing.expectEqualStrings(expected, resolved);
}

test "resolveGeminiHomeFromEnv falls back to USERPROFILE when HOME is unset" {
    const gpa = std.testing.allocator;

    const resolved = try registry.resolveGeminiHomeFromEnv(
        gpa,
        null,
        null,
        "C:\\Users\\demo",
    );
    defer gpa.free(resolved);

    const expected = try fs.path.join(gpa, &[_][]const u8{ "C:\\Users\\demo", ".gemini" });
    defer gpa.free(expected);

    try std.testing.expectEqualStrings(expected, resolved);
}

fn countBackups(dir: fs.Dir, prefix: []const u8) !usize {
    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.startsWith(u8, entry.name, prefix) and std.mem.containsAtLeast(u8, entry.name, 1, ".bak.")) {
            count += 1;
        }
    }
    return count;
}

fn expectBackupNameFormat(name: []const u8, prefix: []const u8) !void {
    const marker = ".bak.";
    try std.testing.expect(std.mem.startsWith(u8, name, prefix));
    const idx = std.mem.indexOf(u8, name, marker) orelse return error.TestExpectedEqual;
    const suffix = name[idx + marker.len ..];

    var stamp = suffix;
    if (std.mem.lastIndexOfScalar(u8, suffix, '.')) |dot_idx| {
        const maybe_counter = suffix[dot_idx + 1 ..];
        if (maybe_counter.len > 0) {
            for (maybe_counter) |ch| {
                if (!std.ascii.isDigit(ch)) return error.TestExpectedEqual;
            }
            stamp = suffix[0..dot_idx];
        }
    }

    if (stamp.len == 15 and stamp[8] == '-') {
        for (0.., stamp) |i, ch| {
            if (i == 8) continue;
            try std.testing.expect(std.ascii.isDigit(ch));
        }
        return;
    }

    try std.testing.expect(stamp.len > 0);
    for (stamp) |ch| {
        try std.testing.expect(std.ascii.isDigit(ch));
    }
}

fn expectModeUnix(path: []const u8, expected_mode: u16) !void {
    if (comptime builtin.os.tag == .windows) return;
    const stat = try fs.cwd().statFile(path);
    try std.testing.expectEqual(@as(std.posix.mode_t, expected_mode), stat.permissions.toMode() & 0o777);
}

fn setModeUnix(path: []const u8, mode: u16) !void {
    if (comptime builtin.os.tag == .windows) return;
    try fs.cwd().inner.setFilePermissions(fs.io(), path, fs.File.Permissions.fromMode(mode), .{});
}

test "registry save/load" {
    var gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    const rec = try makeAccountRecord(gpa, "a@b.com", "work", .pro, 1);
    try reg.accounts.append(gpa, rec);
    const active_account_key = try gpa.dupe(u8, "a@b.com");
    defer gpa.free(active_account_key);
    try registry.setActiveAccountKey(gpa, &reg, active_account_key);
    reg.auto_switch.threshold_5h_percent = 12;
    reg.auto_switch.threshold_weekly_percent = 8;
    reg.api.usage = true;
    try registry.setAccountLastLocalRollout(gpa, &reg.accounts.items[0], "/tmp/sessions/run-1/rollout-a.jsonl", 1735689600000);

    try registry.saveRegistry(gpa, gemini_home, &reg);

    const registry_path = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "accounts", "registry.json" });
    defer gpa.free(registry_path);
    const saved = try fixtures.readFileAlloc(gpa, registry_path);
    defer gpa.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"usage\": true") != null);

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expect(loaded.accounts.items.len == 1);
    try std.testing.expect(loaded.auto_switch.threshold_5h_percent == 12);
    try std.testing.expect(loaded.auto_switch.threshold_weekly_percent == 8);
    try std.testing.expect(loaded.api.usage);
    try std.testing.expect(loaded.api.account);
    try std.testing.expect(loaded.active_account_activated_at_ms != null);
    try std.testing.expect(loaded.accounts.items[0].last_local_rollout != null);
    try std.testing.expectEqual(@as(i64, 1735689600000), loaded.accounts.items[0].last_local_rollout.?.event_timestamp_ms);
    try std.testing.expect(std.mem.eql(u8, loaded.accounts.items[0].last_local_rollout.?.path.?, "/tmp/sessions/run-1/rollout-a.jsonl"));
    try std.testing.expect(loaded.accounts.items[0].account_name == null);
}

test "plan labels are human-readable while registry stores raw plan values" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    try reg.accounts.append(gpa, try makeAccountRecord(gpa, "label@example.com", "", .pro, 1));
    try registry.saveRegistry(gpa, gemini_home, &reg);

    const registry_path = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "accounts", "registry.json" });
    defer gpa.free(registry_path);
    const saved = try fixtures.readFileAlloc(gpa, registry_path);
    defer gpa.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"plan\": \"pro\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"Pro\"") == null);
    try std.testing.expectEqualStrings("Free", registry.planLabel(.free));
    try std.testing.expectEqualStrings("Pro", registry.planLabel(.pro));
    try std.testing.expectEqualStrings("Ultra", registry.planLabel(.ultra));
    try std.testing.expectEqualStrings("Unknown", registry.planLabel(.unknown));
}

test "resolveDisplayPlan prefers a usage snapshot plan over the stored auth plan" {
    const gpa = std.testing.allocator;
    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    var rec = try makeAccountRecord(gpa, "display@example.com", "", .pro, 1);
    rec.last_usage = .{
        .primary = null,
        .secondary = null,
        .credits = null,
        .plan_type = .pro,
    };
    try reg.accounts.append(gpa, rec);

    try std.testing.expectEqual(registry.PlanType.pro, registry.resolvePlan(&reg.accounts.items[0]).?);
    try std.testing.expectEqual(registry.PlanType.pro, registry.resolveDisplayPlan(&reg.accounts.items[0]).?);
}

test "registry load defaults missing account_name field to null" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    try tmp.dir.writeFile(.{
        .sub_path = "accounts/registry.json",
        .data =
            \\{
            \\  "schema_version": 3,
            \\  "active_account_key": null,
            \\  "accounts": [
            \\    {
            \\      "google_user_id": "google_user_123::account_123",
            \\      "account_key": "google_user_123",
            \\      "email": "a@b.com",
            \\      "alias": "work",
            \\      "plan": "pro",
            \\      "created_at": 1,
            \\      "last_used_at": null,
            \\      "last_usage_at": null
            \\    }
            \\  ]
            \\}
            ,
    });

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), loaded.accounts.items.len);
    try std.testing.expect(loaded.accounts.items[0].account_name == null);
}

test "registry save/load round-trips account_name null" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    const rec = try makeAccountRecord(gpa, "a@b.com", "work", .pro, 1);
    try reg.accounts.append(gpa, rec);
    try registry.saveRegistry(gpa, gemini_home, &reg);

    const registry_path = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "accounts", "registry.json" });
    defer gpa.free(registry_path);
    const saved = try fixtures.readFileAlloc(gpa, registry_path);
    defer gpa.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"account_name\": null") != null);

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expect(loaded.accounts.items[0].account_name == null);
}

test "registry save/load round-trips account_name string" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    var rec = try makeAccountRecord(gpa, "a@b.com", "work", .pro, 1);
    rec.account_name = try gpa.dupe(u8, "abcd");
    try reg.accounts.append(gpa, rec);
    try registry.saveRegistry(gpa, gemini_home, &reg);

    const registry_path = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "accounts", "registry.json" });
    defer gpa.free(registry_path);
    const saved = try fixtures.readFileAlloc(gpa, registry_path);
    defer gpa.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"account_name\": \"abcd\"") != null);

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expect(loaded.accounts.items[0].account_name != null);
    try std.testing.expect(std.mem.eql(u8, loaded.accounts.items[0].account_name.?, "abcd"));
}

// Note: Team account tests removed - Gemini doesn't have team accounts like OpenAI

test "registry save/load round-trips api.account false" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);
    reg.api.account = false;

    const rec = try makeAccountRecord(gpa, "a@b.com", "work", .pro, 1);
    try reg.accounts.append(gpa, rec);
    try registry.saveRegistry(gpa, gemini_home, &reg);

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expect(loaded.api.usage);
    try std.testing.expect(!loaded.api.account);
}

test "registry load defaults missing auto threshold fields" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    try tmp.dir.writeFile(.{
        .sub_path = "accounts/registry.json",
        .data =
            \\{
            \\  "schema_version": 3,
            \\  "active_account_key": null,
            \\  "auto_switch": {
            \\    "enabled": true
            \\  },
            \\  "accounts": []
            \\}
            ,
    });

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expect(loaded.auto_switch.enabled);
    try std.testing.expect(loaded.auto_switch.threshold_5h_percent == registry.default_auto_switch_threshold_5h_percent);
    try std.testing.expect(loaded.auto_switch.threshold_weekly_percent == registry.default_auto_switch_threshold_weekly_percent);
    try std.testing.expect(loaded.api.usage);
    try std.testing.expect(loaded.api.account);
    try std.testing.expect(loaded.active_account_activated_at_ms == null);

    const registry_path = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "accounts", "registry.json" });
    defer gpa.free(registry_path);
    const saved = try fixtures.readFileAlloc(gpa, registry_path);
    defer gpa.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"usage\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"account\": true") != null);
}

test "registry load migrates old auto thresholds to default one percent" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    try tmp.dir.writeFile(.{
        .sub_path = "accounts/registry.json",
        .data =
            \\{
            \\  "schema_version": 3,
            \\  "active_account_key": null,
            \\  "auto_switch": {
            \\    "enabled": true,
            \\    "threshold_5h_percent": 12,
            \\    "threshold_weekly_percent": 8
            \\  },
            \\  "accounts": []
            \\}
            ,
    });

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expect(loaded.auto_switch.enabled);
    try std.testing.expectEqual(@as(u8, 1), loaded.auto_switch.threshold_5h_percent);
    try std.testing.expectEqual(@as(u8, 1), loaded.auto_switch.threshold_weekly_percent);

    const registry_path = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "accounts", "registry.json" });
    defer gpa.free(registry_path);
    const saved = try fixtures.readFileAlloc(gpa, registry_path);
    defer gpa.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"schema_version\": 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"threshold_5h_percent\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"threshold_weekly_percent\": 1") != null);
}

test "registry load backfills missing api.account from api.usage and rewrites file" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    try tmp.dir.writeFile(.{
        .sub_path = "accounts/registry.json",
        .data =
            \\{
            \\  "schema_version": 3,
            \\  "active_account_key": null,
            \\  "api": {
            \\    "usage": false
            \\  },
            \\  "accounts": []
            \\}
            ,
    });

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expect(!loaded.api.usage);
    try std.testing.expect(!loaded.api.account);

    const registry_path = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "accounts", "registry.json" });
    defer gpa.free(registry_path);
    const saved = try fixtures.readFileAlloc(gpa, registry_path);
    defer gpa.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"usage\": false") != null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"account\": false") != null);
}

test "registry load backfills missing api.usage from api.account and rewrites file" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    try tmp.dir.writeFile(.{
        .sub_path = "accounts/registry.json",
        .data =
            \\{
            \\  "schema_version": 3,
            \\  "active_account_key": null,
            \\  "api": {
            \\    "account": false
            \\  },
            \\  "accounts": []
            \\}
            ,
    });

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expect(!loaded.api.usage);
    try std.testing.expect(!loaded.api.account);

    const registry_path = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "accounts", "registry.json" });
    defer gpa.free(registry_path);
    const saved = try fixtures.readFileAlloc(gpa, registry_path);
    defer gpa.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"usage\": false") != null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"account\": false") != null);
}

test "legacy schema registry with legacy rollout attribution rewrites to normalized current schema" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    try tmp.dir.writeFile(.{
        .sub_path = "accounts/registry.json",
        .data =
            \\{
            \\  "schema_version": 3,
            \\  "active_account_key": "google_user_123::account_123",
            \\  "last_attributed_rollout": {
            \\    "path": "/tmp/sessions/run-1/rollout-a.jsonl",
            \\    "event_timestamp_ms": 1735689600000
            \\  },
            \\  "accounts": [
            \\    {
            \\      "google_user_id": "google_user_123",
            \\      "account_key": "google_user_123",
            \\      "email": "a@b.com",
            \\      "alias": "work",
            \\      "plan": "pro",
            \\      "created_at": 1,
            \\      "last_used_at": null,
            \\      "last_usage_at": null
            \\    }
            \\  ]
            \\}
            ,
    });

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expectEqual(@as(?i64, 0), loaded.active_account_activated_at_ms);
    try std.testing.expect(loaded.accounts.items[0].last_local_rollout == null);

    var file = try tmp.dir.openFile("accounts/registry.json", .{});
    defer file.close();
    const contents = try file.readToEndAlloc(gpa, 10 * 1024 * 1024);
    defer gpa.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"schema_version\": 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"active_account_activated_at_ms\": 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"last_attributed_rollout\"") == null);
}

test "legacy current-layout registry version field rewrites to schema_version" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    try tmp.dir.writeFile(.{
        .sub_path = "accounts/registry.json",
        .data =
            \\{
            \\  "version": 3,
            \\  "active_account_key": null,
            \\  "auto_switch": {
            \\    "enabled": true
            \\  },
            \\  "accounts": []
            \\}
            ,
    });

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expect(loaded.schema_version == registry.current_schema_version);

    var file = try tmp.dir.openFile("accounts/registry.json", .{});
    defer file.close();
    const contents = try file.readToEndAlloc(gpa, 10 * 1024 * 1024);
    defer gpa.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"schema_version\": 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"version\"") == null);
}

test "too-new schema version is rejected without rewriting registry" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    try tmp.dir.writeFile(.{
        .sub_path = "accounts/registry.json",
        .data =
            \\{
            \\  "schema_version": 999,
            \\  "active_account_key": null,
            \\  "accounts": []
            \\}
            ,
    });

    try std.testing.expectError(error.UnsupportedRegistryVersion, registry.loadRegistry(gpa, gemini_home));

    var file = try tmp.dir.openFile("accounts/registry.json", .{});
    defer file.close();
    const contents = try file.readToEndAlloc(gpa, 10 * 1024 * 1024);
    defer gpa.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"schema_version\": 999") != null);
}

test "v2 registry migrates active email records to current schema" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    const legacy_auth = try fixtures.readFileAlloc(gpa, "tests/fixtures/gemini_auth_sample.json");
    defer gpa.free(legacy_auth);

    try tmp.dir.writeFile(.{ .sub_path = "accounts/registry.json", .data =
        \\{
        \\  "version": 2,
        \\  "active_email": "legacy@example.com",
        \\  "accounts": [
        \\    {
        \\      "email": "legacy@example.com",
        \\      "alias": "work",
        \\      "plan": "team",
        \\      "created_at": 1,
        \\      "last_used_at": null,
        \\      "last_usage_at": null
        \\    }
        \\  ]
        \\}
        , });

    var loaded = try registry.loadRegistry(gpa, gemini_home);
    defer loaded.deinit(gpa);
    try std.testing.expect(loaded.schema_version == registry.current_schema_version);
    try std.testing.expect(loaded.accounts.items.len == 1);
    try std.testing.expect(loaded.active_account_key != null);

    const expected_account_key = try gpa.dupe(u8, "legacy@example.com"); // Simplified for test
    defer gpa.free(expected_account_key);
    try std.testing.expect(std.mem.eql(u8, loaded.active_account_key.?, expected_account_key));

    try std.testing.expect(loaded.active_account_activated_at_ms != null);
}

test "ensureAccountsDir hardens accounts directory without changing gemini home permissions" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(tmp_root);
    try tmp.dir.makePath("gemini-home");

    const gemini_home = try fs.path.join(gpa, &[_][]const u8{ tmp_root, "gemini-home" });
    defer gpa.free(gemini_home);

    try setModeUnix(gemini_home, 0o755);

    try registry.ensureAccountsDir(gpa, gemini_home);

    const accounts_path = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "accounts" });
    defer gpa.free(accounts_path);
    try expectModeUnix(gemini_home, 0o755);
    try expectModeUnix(accounts_path, 0o700);
}

test "copyManagedFile creates destination with 0600 regardless of source mode" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);

    try tmp.dir.writeFile(.{ .sub_path = "source.json", .data = "secret" });
    const src = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "source.json" });
    defer gpa.free(src);
    try setModeUnix(src, 0o644);

    const dest = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "dest.json" });
    defer gpa.free(dest);

    try registry.copyManagedFile(src, dest);
    try expectModeUnix(dest, 0o600);
}

test "saveRegistry creates registry.json with 0600 on first write" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    try registry.saveRegistry(gpa, gemini_home, &reg);

    const registry_path = try registry.registryPath(gpa, gemini_home);
    defer gpa.free(registry_path);
    try expectModeUnix(registry_path, 0o600);
}

test "saveRegistry hardens registry.json to 0600 even when contents are unchanged" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    try registry.saveRegistry(gpa, gemini_home, &reg);

    const registry_path = try registry.registryPath(gpa, gemini_home);
    defer gpa.free(registry_path);
    try setModeUnix(registry_path, 0o644);

    try registry.saveRegistry(gpa, gemini_home, &reg);
    try expectModeUnix(registry_path, 0o600);
}

// Note: Auth backup tests simplified for Gemini (uses oauth_creds.json instead of oauth_creds.json)

test "auth backup only on change" {
    var gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);

    const current = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "oauth_creds.json" });
    defer gpa.free(current);

    try tmp.dir.makePath("accounts");

    try tmp.dir.writeFile(.{ .sub_path = "oauth_creds.json", .data = "one" });
    try tmp.dir.writeFile(.{ .sub_path = "accounts/oauth_creds.json.bak.1", .data = "one" });

    try registry.backupAuthIfChanged(gpa, gemini_home, current, current);
    var accounts = try tmp.dir.openDir("accounts", .{ .iterate = true });
    defer accounts.close();
    const count1 = try countBackups(accounts, "oauth_creds.json");
    try std.testing.expect(count1 == 1);

    try tmp.dir.writeFile(.{ .sub_path = "oauth_creds.json", .data = "two" });

    try registry.backupAuthIfChanged(gpa, gemini_home, current, current);
    accounts = try tmp.dir.openDir("accounts", .{ .iterate = true });
    defer accounts.close();
    const count2 = try countBackups(accounts, "oauth_creds.json");
    try std.testing.expect(count2 == 1);
}

test "auth backup rotation" {
    var gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);

    const current = try fs.path.join(gpa, &[_][]const u8{ gemini_home, "oauth_creds.json" });
    defer gpa.free(current);

    try tmp.dir.makePath("accounts");

    try tmp.dir.writeFile(.{ .sub_path = "accounts/oauth_creds.json.bak.1", .data = "base" });

    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const data = try std.fmt.allocPrint(gpa, "v{d}", .{i});
        defer gpa.free(data);
        try tmp.dir.writeFile(.{ .sub_path = "oauth_creds.json", .data = data });
        try registry.backupAuthIfChanged(gpa, gemini_home, current, current);
    }

    var accounts = try tmp.dir.openDir("accounts", .{ .iterate = true });
    defer accounts.close();
    const count = try countBackups(accounts, "oauth_creds.json");
    try std.testing.expect(count <= 5);
}

test "sync active auth leaves oauth_creds.json permissions unchanged while hardening matching snapshot" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    const rec = try makeAccountRecord(gpa, "user@example.com", "work", .pro, 1);
    try setRecordIds(gpa, &rec, "user@example.com");
    try reg.accounts.append(gpa, rec);
    try registry.setActiveAccountKey(gpa, &reg, reg.accounts.items[0].account_key);

    const active_auth = try fixtures.readFileAlloc(gpa, "tests/fixtures/gemini_auth_sample.json");
    defer gpa.free(active_auth);
    try tmp.dir.writeFile(.{ .sub_path = "oauth_creds.json", .data = active_auth });

    const account_key = try gpa.dupe(u8, "user@example.com");
    defer gpa.free(account_key);
    const snapshot_path = try registry.accountAuthPath(gpa, gemini_home, account_key);
    defer gpa.free(snapshot_path);
    const snapshot_name = fs.path.basename(snapshot_path);
    const snapshot_rel = try fs.path.join(gpa, &[_][]const u8{ "accounts", snapshot_name });
    defer gpa.free(snapshot_rel);
    try tmp.dir.writeFile(.{ .sub_path = snapshot_rel, .data = active_auth });

    const auth_path = try registry.activeAuthPath(gpa, gemini_home);
    defer gpa.free(auth_path);
    try setModeUnix(auth_path, 0o644);
    try setModeUnix(snapshot_path, 0o644);

    const changed = try registry.syncActiveAccountFromAuth(gpa, gemini_home, &reg);
    try std.testing.expect(!changed);
    try expectModeUnix(auth_path, 0o644);
    try expectModeUnix(snapshot_path, 0o600);
}

test "replaceActiveAuthWithAccountByKey preserves existing oauth_creds.json permissions" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    const rec = try makeAccountRecord(gpa, "user@example.com", "work", .pro, 1);
    try setRecordIds(gpa, &rec, "user@example.com");
    try reg.accounts.append(gpa, rec);
    try registry.ensureAccountsDir(gpa, gemini_home);

    const account_auth = try fixtures.readFileAlloc(gpa, "tests/fixtures/gemini_auth_sample.json");
    defer gpa.free(account_auth);
    try tmp.dir.writeFile(.{ .sub_path = "oauth_creds.json", .data = "old" });

    const account_key = try gpa.dupe(u8, "user@example.com");
    defer gpa.free(account_key);
    const snapshot_path = try registry.accountAuthPath(gpa, gemini_home, account_key);
    defer gpa.free(snapshot_path);
    try tmp.dir.writeFile(.{ .sub_path = snapshot_path, .data = account_auth });

    const auth_path = try registry.activeAuthPath(gpa, gemini_home);
    defer gpa.free(auth_path);
    try setModeUnix(auth_path, 0o644);

    try registry.replaceActiveAuthWithAccountByKey(gpa, gemini_home, &reg, account_key);
    try expectModeUnix(auth_path, 0o644);
}

test "activateAccountByKey preserves snapshot permissions when oauth_creds.json is created" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    const rec = try makeAccountRecord(gpa, "user@example.com", "work", .pro, 1);
    try setRecordIds(gpa, &rec, "user@example.com");
    try reg.accounts.append(gpa, rec);
    try registry.ensureAccountsDir(gpa, gemini_home);

    const account_auth = try fixtures.readFileAlloc(gpa, "tests/fixtures/gemini_auth_sample.json");
    defer gpa.free(account_auth);
    try tmp.dir.writeFile(.{ .sub_path = "oauth_creds.json", .data = "old" });

    const account_key = try gpa.dupe(u8, "user@example.com");
    defer gpa.free(account_key);
    const snapshot_path = try registry.accountAuthPath(gpa, gemini_home, account_key);
    defer gpa.free(snapshot_path);
    try tmp.dir.writeFile(.{ .sub_path = snapshot_path, .data = account_auth });
    try setModeUnix(snapshot_path, 0o600);

    const auth_path = try registry.activeAuthPath(gpa, gemini_home);
    defer gpa.free(auth_path);
    try std.testing.expectError(error.FileNotFound, fs.cwd().statFile(auth_path));

    try registry.activateAccountByKey(gpa, gemini_home, &reg, account_key);
    var auth_file = try fs.cwd().openFile(auth_path, .{});
    defer auth_file.close();
    const auth_bytes = try auth_file.readToEndAlloc(gpa, 10 * 1024 * 1024);
    defer gpa.free(auth_bytes);
    try std.testing.expectEqualStrings(account_auth, auth_bytes);
    try expectModeUnix(auth_path, 0o600);
}

test "sync active auth matches by google_user_id and updates account auth" {
    var gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    const rec = try makeAccountRecord(gpa, "user@example.com", "", null, 2);
    try setRecordIds(gpa, &rec, "user@example.com");
    try reg.accounts.append(gpa, rec);

    const account_auth = try fixtures.readFileAlloc(gpa, "tests/fixtures/gemini_auth_sample.json");
    defer gpa.free(account_auth);
    try tmp.dir.writeFile(.{ .sub_path = "oauth_creds.json", .data = account_auth });

    const changed = try registry.syncActiveAccountFromAuth(gpa, gemini_home, &reg);
    try std.testing.expect(changed);
    try std.testing.expect(reg.accounts.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, reg.accounts.items[0].email, "user@example.com"));

    const account_key = try gpa.dupe(u8, "user@example.com");
    defer gpa.free(account_key);
    const acc_path = try registry.accountAuthPath(gpa, gemini_home, account_key);
    defer gpa.free(acc_path);
    var file = try fs.cwd().openFile(acc_path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(gpa, 10 * 1024 * 1024);
    defer gpa.free(data);
    try std.testing.expectEqualStrings(account_auth, data);
}

test "registry backup only on change" {
    var gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    try reg.accounts.append(gpa, try makeAccountRecord(gpa, "a@b.com", "work", .pro, 1));
    try registry.saveRegistry(gpa, gemini_home, &reg);

    var accounts = try tmp.dir.openDir("accounts", .{ .iterate = true });
    defer accounts.close();
    const count0 = try countBackups(accounts, "registry.json");
    try std.testing.expect(count0 == 0);

    const reg_path = try registry.registryPath(gpa, gemini_home);
    defer gpa.free(reg_path);
    try tmp.dir.writeFile(.{ .sub_path = "accounts/registry.json.bak.1", .data = "a1" });

    const saved = try fixtures.readFileAlloc(gpa, reg_path);
    defer gpa.free(saved);
    try tmp.dir.writeFile(.{ .sub_path = reg_path, .data = saved });

    try registry.backupRegistryIfChanged(gpa, gemini_home, reg_path, saved);
    accounts = try tmp.dir.openDir("accounts", .{ .iterate = true });
    defer accounts.close();
    const count1 = try countBackups(accounts, "registry.json");
    try std.testing.expect(count1 == 1);
}

test "registry backup rotation" {
    var gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    try reg.accounts.append(gpa, try makeAccountRecord(gpa, "a@b.com", "work", .pro, 1));
    try registry.saveRegistry(gpa, gemini_home, &reg);

    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const data = try std.fmt.allocPrint(gpa, "v{d}", .{i});
        defer gpa.free(data);
        try tmp.dir.writeFile(.{ .sub_path = "accounts/registry.json", .data = data });
        try registry.backupRegistryIfChanged(gpa, gemini_home, "accounts/registry.json", data);
    }

    var accounts = try tmp.dir.openDir("accounts", .{ .iterate = true });
    defer accounts.close();
    const count = try countBackups(accounts, "registry.json");
    try std.testing.expect(count <= 5);
}

test "clean uses a whitelist and only removes non-current files under accounts" {
    const gpa = std.testing.allocator;
    var tmp = fs.tmpDir(.{});
    defer tmp.cleanup();

    const gemini_home = try app_runtime.realPathFileAlloc(gpa, tmp.dir.inner, ".");
    defer gpa.free(gemini_home);
    try tmp.dir.makePath("accounts");

    var reg = makeEmptyRegistry();
    defer reg.deinit(gpa);

    const keep_record = try makeAccountRecord(gpa, "keep@example.com", "", null, 1);
    try setRecordIds(gpa, &keep_record, "keep@example.com");
    try reg.accounts.append(gpa, keep_record);

    const keep_rel_path = try fs.path.join(gpa, &[_][]const u8{ "accounts", "keep.json" });
    defer gpa.free(keep_rel_path);
    try tmp.dir.writeFile(.{ .sub_path = keep_rel_path, .data = "keep" });

    try tmp.dir.writeFile(.{ .sub_path = "accounts/oauth_creds.json.bak.1", .data = "a1" });
    try tmp.dir.writeFile(.{ .sub_path = "accounts/oauth_creds.json.bak.2", .data = "a2" });
    try tmp.dir.writeFile(.{ .sub_path = "accounts/registry.json.bak.1", .data = "r1" });
    try tmp.dir.writeFile(.{ .sub_path = "accounts/registry.json.bak.2", .data = "r2" });
    try tmp.dir.writeFile(.{ .sub_path = "accounts/" ++ registry.account_lock_file_name, .data = "" });
    try tmp.dir.writeFile(.{ .sub_path = "accounts/notes.txt", .data = "junk" });
    try tmp.dir.makePath("accounts/tmpdir");
    try tmp.dir.writeFile(.{ .sub_path = "accounts/tmpdir/old.txt", .data = "junk" });

    // Note: Removed legacy auth path test - Gemini uses single oauth_creds.json

    const summary = try registry.cleanAccountsBackups(gpa, gemini_home);
    try std.testing.expect(summary.auth_backups_removed == 3);
    try std.testing.expect(summary.registry_backups_removed == 2);
    try std.testing.expect(summary.stale_snapshot_files_removed == 3);

    var accounts = try tmp.dir.openDir("accounts", .{ .iterate = true });
    defer accounts.close();
    try std.testing.expect(try countBackups(accounts, "oauth_creds.json") == 0);

    var keep_file = try tmp.dir.openFile(keep_rel_path, .{});
    keep_file.close();
    var refresh_lock = try tmp.dir.openFile("accounts/" ++ registry.account_lock_file_name, .{});
    refresh_lock.close();
}

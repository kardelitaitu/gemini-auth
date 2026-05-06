const std = @import("std");
const gemini_auth = @import("gemini_auth");

const auto = gemini_auth.auto;
const fixtures = @import("support/fixtures.zig");
const test_fixtures = fixtures;
const registry = gemini_auth.registry;
const CandidateIndex = auto.CandidateIndex;

test "candidate index refreshes cached ranking after a reset window expires" {
    const gpa = std.testing.allocator;

    var reg = fixtures.makeEmptyRegistry();
    defer reg.deinit(gpa);

    try fixtures.appendAccount(gpa, &reg, "active@example.com", "", null);
    try fixtures.appendAccount(gpa, &reg, "reset@example.com", "", null);
    try fixtures.appendAccount(gpa, &reg, "steady@example.com", "", null);

    const active_account_key = try fixtures.accountKeyForEmailAlloc(gpa, "active@example.com");
    defer gpa.free(active_account_key);
    const reset_account_key = try fixtures.accountKeyForEmailAlloc(gpa, "reset@example.com");
    defer gpa.free(reset_account_key);
    const steady_account_key = try fixtures.accountKeyForEmailAlloc(gpa, "steady@example.com");
    defer gpa.free(steady_account_key);

    try registry.setActiveAccountKey(gpa, &reg, active_account_key);

    const reset_idx = registry.findAccountIndexByAccountKey(&reg, reset_account_key) orelse return error.TestExpectedEqual;
    reg.accounts.items[reset_idx].last_usage = .{
        .primary = .{ .used_percent = 95.0, .window_minutes = 300, .resets_at = 1010 },
        .secondary = null,
        .credits = null,
        .plan_type = .pro,
    };
    reg.accounts.items[reset_idx].last_usage_at = 100;

    const steady_idx = registry.findAccountIndexByAccountKey(&reg, steady_account_key) orelse return error.TestExpectedEqual;
    reg.accounts.items[steady_idx].last_usage = .{
        .primary = .{ .used_percent = 60.0, .window_minutes = 300, .resets_at = null },
        .secondary = null,
        .credits = null,
        .plan_type = .pro,
    };
    reg.accounts.items[steady_idx].last_usage_at = 50;

    var index = CandidateIndex{};
    defer index.deinit(gpa);

    try index.rebuild(gpa, &reg, 1000);
    try std.testing.expect(index.best() != null);
    try std.testing.expect(std.mem.eql(u8, index.best().?.account_key, steady_account_key));

    try index.rebuildIfScoreExpired(gpa, &reg, 1011);
    try std.testing.expect(index.best() != null);
    try std.testing.expect(std.mem.eql(u8, index.best().?.account_key, reset_account_key));
}

pub fn fuzzCandidateScore(input: []const u8) !void {
    // Fuzz inputs: now (i64), has_usage (bool), and usage data
    if (input.len < 9) return; // Need at least 8 bytes for now + 1 for has_usage

    const now = std.mem.readIntLittle(i64, input[0..8]);
    const has_usage = input[8] & 1 != 0;

    var rec: registry.AccountRecord = .{
        .account_key = "test",
        .email = "test@example.com",
        .alias = "test",
        .created_at = 0,
        .last_used_at = null,
        .last_usage_at = null,
        .last_usage = null,
        .last_local_rollout = null,
        .plan = null,
    };

    if (has_usage and input.len >= 8 + 1 + 8 + 8 + 8) { // has_usage + used_percent (f64) + window_minutes (i64) + resets_at (i64)
        const used_percent = std.mem.readIntLittle(f64, input[9..17]);
        const window_minutes = std.mem.readIntLittle(i64, input[17..25]);
        const resets_at = std.mem.readIntLittle(i64, input[25..33]);

        rec.last_usage = .{
            .primary = .{ .used_percent = used_percent, .window_minutes = window_minutes, .resets_at = resets_at },
            .secondary = null,
            .credits = null,
            .plan_type = .free,
        };
        rec.last_usage_at = 0;
    }

    const score = auto.candidateScore(&rec, now);

    // Invariants: score.value should be non-negative, and within reasonable bounds
    std.debug.assert(score.value >= 0);
    std.debug.assert(score.value <= 100); // Assuming usage score is percentage
    std.debug.assert(score.last_usage_at >= -1); // -1 for null
    std.debug.assert(score.created_at >= 0);
}

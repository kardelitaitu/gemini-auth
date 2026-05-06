const std = @import("std");
const http = @import("http.zig");
const registry = @import("../registry/root.zig");

// TBD: Update with actual Gemini API endpoints
pub const default_usage_endpoint = "https://gemini.google.com/v1/usage";

pub const UsageFetchResult = struct {
    snapshot: ?registry.RateLimitSnapshot,
    status_code: ?u16,
    error_code: ?ResponseErrorCode = null,
    error_name: ?[]const u8 = null,
    missing_auth: bool = false,

    pub fn deinit(self: *const UsageFetchResult, allocator: std.mem.Allocator) void {
        if (self.snapshot) |*snap| registry.freeRateLimitSnapshot(allocator, snap);
        if (self.error_name) |name| allocator.free(name);
    }
};

pub const ResponseErrorCode = enum {
    rate_limited,
    server_error,
    auth_error,
    unknown,

    pub fn text(self: ResponseErrorCode) []const u8 {
        return switch (self) {
            .rate_limited => "rate_limited",
            .server_error => "server_error",
            .auth_error => "auth_error",
            .unknown => "unknown",
        };
    }
};

pub const BatchUsageFetchResult = []UsageFetchResult;

fn freeRateLimitSnapshot(allocator: std.mem.Allocator, snap: *const registry.RateLimitSnapshot) void {
    _ = allocator;
    _ = snap;
    // TBD: Implement when Gemini API structure is known
}

pub fn fetchUsageForToken(
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    access_token: []const u8,
) !UsageFetchResult {
    _ = allocator;
    _ = endpoint;
    _ = access_token;
    // TBD: Implement Gemini API call
    return .{ .snapshot = null, .status_code = 200, .missing_auth = false };
}

pub fn fetchUsageForTokenDetailed(
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    access_token: []const u8,
    account_id: []const u8,
) !UsageFetchResult {
    _ = account_id;
    return fetchUsageForToken(allocator, endpoint, access_token);
}

pub fn fetchActiveUsage(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
) !?registry.RateLimitSnapshot {
    _ = allocator;
    _ = gemini_home;
    // TBD: Implement when Gemini API is available
    return null;
}

pub fn fetchActiveUsageDetailed(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
) !UsageFetchResult {
    _ = allocator;
    _ = gemini_home;
    // TBD: Implement when Gemini API is available
    return .{ .snapshot = null, .status_code = null };
}

pub fn fetchUsageForAuthPathDetailed(
    allocator: std.mem.Allocator,
    auth_path: []const u8,
) !UsageFetchResult {
    _ = allocator;
    _ = auth_path;
    // TBD: Implement when Gemini API is available
    return .{ .snapshot = null, .status_code = null, .missing_auth = false };
}

pub fn fetchUsageForAuthPathsDetailedBatch(
    allocator: std.mem.Allocator,
    auth_paths: []const []const u8,
    concurrency: usize,
) !BatchUsageFetchResult {
    _ = allocator;
    _ = auth_paths;
    _ = concurrency;
    // TBD: Implement when Gemini API is available
    return &[_]UsageFetchResult{};
}

// Stub function for tests - parse usage response (simplified)
pub fn parseUsageResponse(
    allocator: std.mem.Allocator,
    body: []const u8,
) !?registry.RateLimitSnapshot {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const root = parsed.value;

    if (root != .object) return null;
    const obj = root.object;

    // Parse plan_type
    const plan_type_str = if (obj.get("plan_type")) |pt| switch (pt) {
        .string => |s| s,
        else => return null,
    } else null;

    const plan_type = if (plan_type_str) |s| blk: {
        if (std.mem.eql(u8, s, "free")) break :blk registry.PlanType.free;
        if (std.mem.eql(u8, s, "pro")) break :blk registry.PlanType.pro;
        if (std.mem.eql(u8, s, "ultra")) break :blk registry.PlanType.ultra;
        break :blk null;
    } else null;

    // Parse rate_limit
    const rate_limit = obj.get("rate_limit") orelse return registry.RateLimitSnapshot{
        .primary = null,
        .secondary = null,
        .credits = null,
        .plan_type = plan_type,
    };

    if (rate_limit == .null) return null;

    if (rate_limit != .object) return null;
    const rl_obj = rate_limit.object;

    const used_percent = if (rl_obj.get("used_percent")) |up| switch (up) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => return null,
    } else return null;

    const window_seconds = if (rl_obj.get("window_seconds")) |ws| switch (ws) {
        .integer => |i| i,
        else => return null,
    } else null;

    const reset_at = if (rl_obj.get("reset_at")) |ra| switch (ra) {
        .integer => |i| i,
        else => null,
    } else null;

    const window_minutes = if (window_seconds) |ws| @divFloor(ws, 60) else null;

    const primary = registry.RateLimitWindow{
        .used_percent = used_percent,
        .window_minutes = window_minutes,
        .resets_at = reset_at,
    };

    return registry.RateLimitSnapshot{
        .primary = primary,
        .secondary = null,
        .credits = null,
        .plan_type = plan_type,
    };
}

// Stub function for tests - parse error code
pub fn parseNonSuccessErrorCode(
    allocator: std.mem.Allocator,
    status_code: u16,
) ?[]const u8 {
    _ = allocator;
    if (status_code == 429) return "rate_limited";
    return null;
}

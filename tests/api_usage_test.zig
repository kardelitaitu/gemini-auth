const std = @import("std");
const usage_api = @import("gemini_auth").api.usage;
const registry = @import("gemini_auth").registry;

test "parse usage api response maps plan" {
    const gpa = std.testing.allocator;

    // Gemini API format is TBD (To Be Determined)
    // For now, test basic structure
    const body =
        \\{
        \\  "plan_type": "pro",
        \\  "rate_limit": {
        \\    "used_percent": 11,
        \\    "window_seconds": 18000,
        \\    "reset_after_seconds": 16802,
        \\    "reset_at": 1773491460
        \\  }
        \\}
    ;

    const snapshot = (try usage_api.parseUsageResponse(gpa, body)) orelse return error.TestExpectedEqual;
    defer registry.freeRateLimitSnapshot(gpa, &snapshot);

    try std.testing.expect(registry.PlanType.pro == snapshot.plan_type.?);
    try std.testing.expectEqual(@as(f64, 11.0), snapshot.primary.?.used_percent);
}

test "parse usage api response without windows is ignored" {
    const gpa = std.testing.allocator;

    const body =
        \\{
        \\  "plan_type": "free",
        \\  "rate_limit": null
        \\}
    ;

    const snapshot = usage_api.parseUsageResponse(gpa, body);
    try std.testing.expect(snapshot == null);
}

test "parse usage api response maps ultra plan" {
    const gpa = std.testing.allocator;

    const body =
        \\{
        \\  "plan_type": "ultra",
        \\  "rate_limit": {
        \\    "used_percent": 0,
        \\    "window_seconds": 604800,
        \\    "reset_after_seconds": 604800,
        \\    "reset_at": 1774079459`
        \\  }
        \\}
    ;

    const snapshot = (try usage_api.parseUsageResponse(gpa, body)) orelse return error.TestExpectedEqual;
    defer registry.freeRateLimitSnapshot(gpa, &snapshot);

    try std.testing.expect(registry.PlanType.ultra == snapshot.plan_type.?);
}

test "parse usage api response maps free plan" {
    const gpa = std.testing.allocator;

    const body =
        \\{
        \\  "plan_type": "free",
        \\  "rate_limit": {
        \\    "used_percent": 5,
        \\    "window_seconds": 604800,
        \\    "reset_after_seconds": 274961,
        \\    "reset_at": 1773749620`
        \\  }
        \\}
    ;

    const snapshot = (try usage_api.parseUsageResponse(gpa, body)) orelse return error.TestExpectedEqual;
    defer registry.freeRateLimitSnapshot(gpa, &snapshot);

    try std.testing.expect(registry.PlanType.free == snapshot.plan_type.?);
}

test "parse invalid json returns null" {
    const gpa = std.testing.allocator;

    const body = "not json";
    const snapshot = usage_api.parseUsageResponse(gpa, body);
    try std.testing.expect(snapshot == null);
}

// Note: Gemini API format is TBD
// These tests use a hypothetical format
// Update when actual Gemini API responses are available

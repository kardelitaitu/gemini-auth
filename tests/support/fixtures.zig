const std = @import("std");
const app_runtime = @import("gemini_auth").core.runtime;
const compat_fs = @import("gemini_auth").core.compat_fs;
const fs = @import("gemini_auth").core.compat_fs;
const registry = @import("gemini_auth").registry;

pub fn makeEmptyRegistry() registry.Registry {
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

pub fn b64url(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const encoder = std.base64.url_safe_no_pad.Encoder;
    const out_len = encoder.calcSize(input.len);
    const buf = try allocator.alloc(u8, out_len);
    _ = encoder.encode(buf, input);
    return buf;
}

// Generate a Gemini OAuth2 test auth JSON
pub fn geminiAuthForEmailAlloc(
    allocator: std.mem.Allocator,
    email: []const u8,
) ![]u8 {
    // Create a Google-like JWT payload
    const header = "{\"alg\":\"RS256\",\"kid\":\"19caaecde8f485e8f5938f48aba0ce7a358f1f0f7\"}";
    const payload_str = try std.fmt.allocPrint(
        allocator,
        "{{\"iss\":\"https://accounts.google.com\",\"azp\":\"681255809395-o8oft2orprdnp9e3aqfj6av3nhmdib135j.apps.googleusercontent.com\",\"aud\":\"681255809395-o8oft2orprdnp9e3aqfj6av3nhmdib135j.apps.googleusercontent.com\",\"sub\":\"{s}\",\"email\":\"{s}\",\"name\":\"Test User\"}}",
        .{ "10990001336791434215", email },
    );
    defer allocator.free(payload_str);

    const h64 = try b64url(allocator, header);
    defer allocator.free(h64);
    const p64 = try b64url(allocator, payload_str);
    defer allocator.free(p64);

    const jwt = try std.mem.concat(allocator, u8, &[_][]const u8{ h64, ".", p64, ".fake_sig" });
    defer allocator.free(jwt);

    // Return Gemini OAuth2 format
    return try std.fmt.allocPrint(
        allocator,
        "{{\"access_token\":\"ya29.a0.test-{s}\",\"scope\":\"https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email openid\",\"token_type\":\"Bearer\",\"id_token\":\"{s}\",\"expiry_date\":{d},\"refresh_token\":\"1//0test-refresh-{s}\"}}",
        .{ email, jwt, 1640995200000 + 3600000, email },
    );
}

// For tests that need a file path
pub fn geminiAuthPathAlloc(allocator: std.mem.Allocator) ![]u8 {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const auth_data = try geminiAuthForEmailAlloc(allocator, "test@example.com");
    defer allocator.free(auth_data);

    {
        var file = try tmp.dir.createFile(app_runtime.io(), "oauth_creds.json", .{});
        defer file.close();
        try file.writeAll(auth_data);
    }

    return try app_runtime.realPathFileAlloc(allocator, tmp.dir, "oauth_creds.json");
}

// Helper to create Google user ID from email (simplified)
fn hashPart(seed: u64, email: []const u8, modulus: u64) u64 {
    return std.hash.Wyhash.hash(seed, email) % modulus;
}

// For backward compatibility with existing tests that expect account keys
pub fn accountKeyForEmailAlloc(allocator: std.mem.Allocator, email: []const u8) ![]u8 {
    // For Gemini, use google_user_id as account_key
    return std.fmt.allocPrint(
        allocator,
        "{d:0>8}-{d:0>4}-{d:0>4}-{d:0>4}-{d:0>12}",
        .{
            hashPart(1, email, 100_000_000),
            hashPart(2, email, 10_000),
            4000 + hashPart(3, email, 1000),
            8000 + hashPart(4, email, 1000),
            hashPart(5, email, 1_000_000_000_000),
        },
    );
}

// Create a test AccountRecord for Gemini
pub fn makeGeminiAccountRecord(
    allocator: std.mem.Allocator,
    email: []const u8,
    alias: []const u8,
    plan: ?registry.PlanType,
) !registry.AccountRecord {
    const google_user_id = try accountKeyForEmailAlloc(allocator, email);
    errdefer allocator.free(google_user_id);

    return registry.AccountRecord{
        .account_key = try allocator.dupe(u8, google_user_id),
        .google_user_id = try allocator.dupe(u8, google_user_id),
        .email = try allocator.dupe(u8, email),
        .alias = try allocator.dupe(u8, alias),
        .name = null,
        .account_name = null,
        .plan = plan,
        .created_at = 1640995200000, // 2022-01-01 in milliseconds
        .last_used_at = null,
        .last_usage = null,
        .last_usage_at = null,
        .last_local_rollout = null,
    };
}

// Generate a Gemini OAuth2 test auth JSON with email and plan (for legacy compatibility)
pub fn authJsonWithEmailPlan(
    allocator: std.mem.Allocator,
    email: []const u8,
    plan: []const u8,
) ![]u8 {
    _ = plan; // Currently unused but kept for API compatibility
    // Use Gemini OAuth2 format
    return geminiAuthForEmailAlloc(allocator, email);
}

// Generate a Gemini OAuth2 test auth JSON without email
pub fn authJsonWithoutEmail(allocator: std.mem.Allocator) ![]u8 {
    // Create JSON without id_token (which contains email)
    return std.fmt.allocPrint(
        allocator,
        "{{\"access_token\":\"ya29.a0.test-no-email\",\"scope\":\"https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email openid\",\"token_type\":\"Bearer\",\"refresh_token\":\"1//0test-refresh-no-email\",\"expiry_date\":{d}}}",
        .{1640995200000 + 3600000},
    );
}

// Generate a Gemini OAuth2 test auth JSON without email for specific email (for testing)
pub fn authJsonWithoutEmailForEmail(
    allocator: std.mem.Allocator,
    email: []const u8,
    plan: []const u8,
) ![]u8 {
    _ = email; // Currently unused but kept for API compatibility
    _ = plan; // Currently unused but kept for API compatibility
    // Same as authJsonWithoutEmail for now
    return authJsonWithoutEmail(allocator);
}

// Generate a CPA (CLI Proxy API) test auth JSON (simplified for Gemini)
pub fn cpaJsonWithEmailPlan(
    allocator: std.mem.Allocator,
    email: []const u8,
    plan: []const u8,
) ![]u8 {
    // For Gemini, CPA format is not used, but provide a similar structure for tests
    return std.fmt.allocPrint(
        allocator,
        "{{\"email\":\"{s}\",\"plan\":\"{s}\",\"access_token\":\"cpa-test-token\"}}",
        .{ email, plan },
    );
}

// Generate a CPA test auth JSON without refresh_token
pub fn cpaJsonWithoutRefreshToken(
    allocator: std.mem.Allocator,
    email: []const u8,
    plan: []const u8,
) ![]u8 {
    // Similar to cpaJsonWithEmailPlan but without refresh_token
    return std.fmt.allocPrint(
        allocator,
        "{{\"email\":\"{s}\",\"plan\":\"{s}\",\"access_token\":\"cpa-test-token\"}}",
        .{ email, plan },
    );
}

// Generate auth JSON without account ID (for testing legacy imports)
pub fn authJsonWithoutAccountId(
    allocator: std.mem.Allocator,
    email: []const u8,
    plan: []const u8,
) ![]u8 {
    // Similar to authJsonWithEmailPlan but without google_user_id
    const jwt = try std.fmt.allocPrint(
        allocator,
        "{{\"email\":\"{s}\",\"plan\":\"{s}\"}}",
        .{ email, plan },
    );
    defer allocator.free(jwt);

    const header = "{\"alg\":\"none\",\"typ\":\"JWT\"}";
    const header_b64 = try b64url(allocator, header);
    defer allocator.free(header_b64);
    const payload_b64 = try b64url(allocator, jwt);
    defer allocator.free(payload_b64);

    return std.mem.concat(allocator, u8, &[_][]const u8{ header_b64, ".", payload_b64, ".sig" });
}

// Helper to append an account to registry for tests
pub fn appendAccount(
    allocator: std.mem.Allocator,
    reg: *registry.Registry,
    email: []const u8,
    alias: ?[]const u8,
    plan: ?registry.PlanType,
) !void {
    const account = try makeGeminiAccountRecord(allocator, email, alias orelse "", plan);
    try reg.accounts.append(allocator, account);
}

// Read file content for tests
pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try compat_fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 1024 * 1024);
}

// Find account index by email for tests
pub fn findAccountIndexByEmail(reg: *registry.Registry, email: []const u8) ?usize {
    for (reg.accounts.items, 0..) |account, i| {
        if (std.mem.eql(u8, account.email, email)) {
            return i;
        }
    }
    return null;
}

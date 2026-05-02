const std = @import("std");
const http = @import("http.zig");

// TBD: Update with actual Gemini API endpoints
pub const account_endpoint = "https://gemini.google.com/v1/accounts";

pub const AccountEntry = struct {
    account_id: []u8,
    account_name: ?[]u8,

    pub fn deinit(self: *const AccountEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.account_id);
        if (self.account_name) |name| allocator.free(name);
    }
};

pub const FetchResult = struct {
    entries: ?[]AccountEntry,
    status_code: ?u16,

    pub fn deinit(self: *const FetchResult, allocator: std.mem.Allocator) void {
        if (self.entries) |entries| {
            for (entries) |*entry| entry.deinit(allocator);
            allocator.free(entries);
        }
    }
};

pub fn fetchAccountsForToken(
    allocator: std.mem.Allocator,
    access_token: []const u8,
) !?[]AccountEntry {
    const http_result = try http.runGetJson(allocator, account_endpoint, access_token);
    defer allocator.free(http_result.body);

    if (http_result.status_code != 200) return null;

    return try parseAccountsResponse(allocator, http_result.body);
}

fn parseAccountsResponse(allocator: std.mem.Allocator, body: []const u8) !?[]AccountEntry {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return null;
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |obj| obj,
        else => return null,
    };

    var entries = std.ArrayList(AccountEntry).init(allocator);
    errdefer {
        for (entries.items) |*entry| entry.deinit(allocator);
        entries.deinit();
    }

    // TBD: Parse actual Gemini API response format
    // For now, return empty list since Gemini doesn't have team accounts like OpenAI

    return entries.toOwnedSlice();
}

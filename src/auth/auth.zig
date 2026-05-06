const std = @import("std");
const app_runtime = @import("../core/runtime.zig");
const registry = @import("../registry/root.zig");

pub const AuthInfo = struct {
    email: ?[]u8,
    google_user_id: ?[]u8,
    name: ?[]u8,
    access_token: ?[]u8,
    refresh_token: ?[]u8,
    id_token: ?[]u8,
    expiry_date: ?i64,
    last_refresh: ?[]u8,

    pub fn deinit(self: *const AuthInfo, allocator: std.mem.Allocator) void {
        if (self.email) |e| allocator.free(e);
        if (self.google_user_id) |id| allocator.free(id);
        if (self.name) |n| allocator.free(n);
        if (self.access_token) |t| allocator.free(t);
        if (self.refresh_token) |t| allocator.free(t);
        if (self.id_token) |t| allocator.free(t);
        if (self.last_refresh) |v| allocator.free(v);
    }
};

pub fn parseAuthInfo(allocator: std.mem.Allocator, auth_path: []const u8) !AuthInfo {
    const abs_path = try app_runtime.realPathFileAlloc(allocator, auth_path);
    defer allocator.free(abs_path);
    const file = try std.fs.openFileAbsolute(abs_path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(data);

    return try parseAuthInfoData(allocator, data);
}

pub fn parseAuthInfoData(allocator: std.mem.Allocator, data: []const u8) !AuthInfo {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer parsed.deinit();
    const root = parsed.value;
    switch (root) {
        .object => |obj| {
            // Parse flat OAuth2 structure
            const access_token = jsonStringField(obj, "access_token");
            const refresh_token = jsonStringField(obj, "refresh_token");
            const id_token = jsonStringField(obj, "id_token");
            const expiry_date = if (obj.get("expiry_date")) |ed| switch (ed) {
                .integer => |i| i,
                .float => |f| @as(i64, @intFromFloat(f)),
                else => null,
            } else null;

            // Decode JWT id_token to get user info
            var email: ?[]u8 = null;
            defer if (email) |e| allocator.free(e);
            var google_user_id: ?[]u8 = null;
            defer if (google_user_id) |id| allocator.free(id);
            var name: ?[]u8 = null;
            defer if (name) |n| allocator.free(n);

            if (id_token) |jwt| {
                const payload = decodeJwtPayload(allocator, jwt) catch |err| {
                    std.log.warn("Failed to decode id_token: {s}", .{@errorName(err)});
                    return AuthInfo{
                        .email = null,
                        .google_user_id = null,
                        .name = null,
                        .access_token = if (access_token) |t| allocator.dupe(u8, t) catch null else null,
                        .refresh_token = if (refresh_token) |t| allocator.dupe(u8, t) catch null else null,
                        .id_token = if (id_token) |t| allocator.dupe(u8, t) catch null else null,
                        .expiry_date = expiry_date,
                        .last_refresh = null,
                    };
                };
                defer allocator.free(payload);

                var payload_json = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
                defer payload_json.deinit();

                const claims = payload_json.value;
                switch (claims) {
                    .object => |cobj| {
                        if (cobj.get("email")) |e| {
                            switch (e) {
                                .string => |s| {
                                    if (s.len > 0) {
                                        email = normalizeEmailAlloc(allocator, s) catch null;
                                    }
                                },
                                else => {},
                            }
                        }
                        if (cobj.get("sub")) |uid| {
                            switch (uid) {
                                .string => |s| {
                                    if (s.len > 0) {
                                        google_user_id = allocator.dupe(u8, s) catch null;
                                    }
                                },
                                else => {},
                            }
                        }
                        if (cobj.get("name")) |n| {
                            switch (n) {
                                .string => |s| {
                                    if (s.len > 0) {
                                        name = allocator.dupe(u8, s) catch null;
                                    }
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            }

            return AuthInfo{
                .email = if (email) |e| blk: { defer allocator.free(e); email = null; break :blk try allocator.dupe(u8, e); } else null,
                .google_user_id = if (google_user_id) |id| blk: { defer allocator.free(id); google_user_id = null; break :blk try allocator.dupe(u8, id); } else null,
                .name = if (name) |n| blk: { defer allocator.free(n); name = null; break :blk try allocator.dupe(u8, n); } else null,
                .access_token = if (access_token) |t| try allocator.dupe(u8, t) else null,
                .refresh_token = if (refresh_token) |t| try allocator.dupe(u8, t) else null,
                .id_token = if (id_token) |t| try allocator.dupe(u8, t) else null,
                .expiry_date = expiry_date,
                .last_refresh = null,
            };
        },
        else => {},
    }

    return AuthInfo{
        .email = null,
        .google_user_id = null,
        .name = null,
        .access_token = null,
        .refresh_token = null,
        .id_token = null,
        .expiry_date = null,
        .last_refresh = null,
    };
}

pub fn decodeJwtPayload(allocator: std.mem.Allocator, jwt: []const u8) ![]u8 {
    var it = std.mem.splitScalar(u8, jwt, '.');
    _ = it.next();
    const payload_b64 = it.next() orelse return error.InvalidJwt;
    _ = it.next() orelse return error.InvalidJwt;

    const decoded = try base64UrlNoPadDecode(allocator, payload_b64);
    return decoded;
}

fn base64UrlNoPadDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoder = std.base64.url_safe_no_pad.Decoder;
    const out_len = decoder.calcSizeForSlice(input) catch return error.InvalidBase64;
    const buf = try allocator.alloc(u8, out_len);
    errdefer allocator.free(buf);
    decoder.decode(buf, input) catch return error.InvalidBase64;
    return buf;
}

fn normalizeEmailAlloc(allocator: std.mem.Allocator, email: []const u8) ![]u8 {
    var buf = try allocator.alloc(u8, email.len);
    for (email, 0..) |ch, i| {
        buf[i] = std.ascii.toLower(ch);
    }
    return buf;
}

fn jsonStringField(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

const std = @import("std");
const app_runtime = @import("../core/runtime.zig");
const auth = @import("auth.zig");
const registry = @import("../registry/root.zig");

pub const BackgroundRefreshLock = struct {
    file: std.Io.File,

    pub fn acquire(allocator: std.mem.Allocator, gemini_home: []const u8) !?BackgroundRefreshLock {
        try registry.ensureAccountsDir(allocator, gemini_home);
        const path = try std.fs.path.join(allocator, &[_][]const u8{
            gemini_home,
            "accounts",
            registry.account_name_refresh_lock_file_name,
        });
        defer allocator.free(path);

        var file = try std.Io.Dir.cwd().createFile(app_runtime.io(), path, .{ .read = true, .truncate = false });
        errdefer file.close(app_runtime.io());
        if (!(try tryExclusiveLock(file))) {
            file.close(app_runtime.io());
            return null;
        }
        return .{ .file = file };
    }

    pub fn release(self: *BackgroundRefreshLock) void {
        self.file.unlock(app_runtime.io());
        self.file.close(app_runtime.io());
    }
};

pub const Candidate = struct {
    google_user_id: []u8,

    pub fn deinit(self: *const Candidate, allocator: std.mem.Allocator) void {
        allocator.free(self.google_user_id);
    }
};

fn hasCandidate(candidates: []const Candidate, google_user_id: []const u8) bool {
    for (candidates) |candidate| {
        if (std.mem.eql(u8, candidate.google_user_id, google_user_id)) return true;
    }
    return false;
}

fn candidateIsNewer(candidate: *const auth.AuthInfo, best: *const auth.AuthInfo) bool {
    const candidate_refresh = candidate.last_refresh orelse return false;
    const best_refresh = best.last_refresh orelse return true;
    return std.mem.order(u8, candidate_refresh, best_refresh) == .gt;
}

fn tryExclusiveLock(file: std.Io.File) !bool {
    return try file.tryLock(app_runtime.io(), .exclusive);
}

pub fn collectCandidates(
    allocator: std.mem.Allocator,
    reg: *registry.Registry,
) !std.ArrayList(Candidate) {
    var candidates = std.ArrayList(Candidate).empty;
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }

    // Gemini doesn't have team accounts like OpenAI
    // Return empty list for now
    return candidates;
}

pub fn loadStoredAuthInfoForUser(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    google_user_id: []const u8,
) !?auth.AuthInfo {
    var best_info: ?auth.AuthInfo = null;
    errdefer if (best_info) |*info| info.deinit(allocator);

    for (reg.accounts.items) |rec| {
        if (!std.mem.eql(u8, rec.google_user_id, google_user_id)) continue;

        const auth_path = try registry.accountAuthPath(allocator, gemini_home, rec.account_key);
        defer allocator.free(auth_path);

        const info = auth.parseAuthInfo(allocator, auth_path) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.FileNotFound => continue,
            else => {
                std.log.warn("account metadata refresh skipped: {s}", .{@errorName(err)});
                continue;
            },
        };
        considerStoredAuthInfoForRefresh(allocator, &best_info, info);
    }

    return best_info;
}

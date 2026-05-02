const std = @import("std");
const app_runtime = @import("../core/runtime.zig");
const registry = @import("../registry/root.zig");
const sessions = @import("../session.zig");
const usage_api = @import("../api/usage.zig");
const files = @import("files.zig");
const logging = @import("logging.zig");
const state = @import("state.zig");

const DaemonRefreshState = state.DaemonRefreshState;
const api_refresh_interval_ns = state.api_refresh_interval_ns;
const fileMtimeNsIfExists = files.fileMtimeNsIfExists;
const emitDaemonLog = logging.emitDaemonLog;
const emitTaggedDaemonLog = logging.emitTaggedDaemonLog;
const localDateTimeLabel = logging.localDateTimeLabel;
const rolloutFileLabel = logging.rolloutFileLabel;
const rolloutWindowsLabel = logging.rolloutWindowsLabel;
const apiStatusLabel = logging.apiStatusLabel;
const fieldSeparator = logging.fieldSeparator;

pub fn refreshActiveUsage(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
) !bool {
    _ = allocator;
    _ = gemini_home;
    _ = reg;
    // TBD: Implement when Gemini API is available
    return false;
}

fn fetchActiveUsage(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    fetcher: anytype,
) !usage_api.FetchResult {
    _ = allocator;
    _ = gemini_home;
    _ = reg;
    // TBD: Implement when Gemini API is available
    return .{ .snapshot = null, .status_code = null };
}

pub fn refreshActiveUsageWithApiFetcher(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    api_fetcher: anytype,
) !?registry.RateLimitSnapshot {
    if (!reg.api.usage) return null;

    const latest_usage = api_fetcher(allocator, gemini_home) catch return null;
    if (latest_usage == null) return null;

    const account_key = reg.active_account_key orelse return null;
    const idx = registry.findAccountIndexByAccountKey(reg, account_key) orelse return null;

    if (registry.rateLimitSnapshotsEqual(reg.accounts.items[idx].last_usage, latest_usage.?)) return null;

    registry.updateUsage(allocator, reg, account_key, latest_usage.?);
    return latest_usage;
}

pub fn refreshActiveUsageForDaemon(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    refresh_state: *DaemonRefreshState,
) !bool {
    if (refreshActiveUsageFromApi(allocator, gemini_home, reg, refresh_state)) return true;
    return refreshActiveUsageFromSessions(allocator, gemini_home, reg, refresh_state);
}

fn refreshActiveUsageFromApi(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    refresh_state: *DaemonRefreshState,
) !bool {
    if (!reg.api.usage) return false;

    const now_ns = @as(i128, std.Io.Timestamp.now(app_runtime.io(), .real).toNanoseconds());
    if (refresh_state.last_api_refresh_at_ns != 0 and (now_ns - refresh_state.last_api_refresh_at_ns) < api_refresh_interval_ns) {
        return false;
    }

    const result = fetchActiveUsage(allocator, gemini_home, reg, usage_api.fetchActiveUsage) catch |err| {
        emitTaggedDaemonLog(.warning, "api", "refresh usage{s}status={s}", .{
            fieldSeparator(),
            @errorName(err),
        });
        return false;
    };
    defer result.deinit(allocator);

    if (result.status_code != null and result.status_code.? != 200) {
        emitTaggedDaemonLog(.warning, "api", "refresh usage{s}status={d}", .{
            fieldSeparator(),
            result.status_code.?,
        });
        return false;
    }

    const snapshot = result.snapshot orelse return false;
    const account_key = reg.active_account_key orelse return false;
    const idx = registry.findAccountIndexByAccountKey(reg, account_key) orelse return false;

    if (registry.rateLimitSnapshotsEqual(reg.accounts.items[idx].last_usage, snapshot)) return false;

    registry.updateUsage(allocator, reg, account_key, snapshot);
    refresh_state.last_api_refresh_at_ns = now_ns;
    return true;
}

fn refreshActiveUsageFromSessions(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    refresh_state: *DaemonRefreshState,
) !bool {
    const latest = sessions.scanLatestUsageWithSource(allocator, gemini_home) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => {
            emitTaggedDaemonLog(.warning, "local", "refresh usage{s}status={s}", .{
                fieldSeparator(),
                @errorName(err),
            });
            return false;
        },
    };
    defer latest.deinit(allocator);

    const event_timestamp_ms = latest.event_timestamp_ms;
    const account_key = reg.active_account_key orelse return false;
    const activated_at_ms = reg.active_account_activated_at_ms orelse 0;

    if (event_timestamp_ms < activated_at_ms) return false;

    const signature: registry.RolloutSignature = .{
        .path = try allocator.dupe(u8, latest.path) catch |err| {
            emitTaggedDaemonLog(.warning, "local", "refresh usage{s}status={s}", .{
                fieldSeparator(),
                @errorName(err),
            });
            return false;
        },
        .event_timestamp_ms = event_timestamp_ms,
    };
    errdefer registry.freeRolloutSignature(allocator, &signature);

    const idx = registry.findAccountIndexByAccountKey(reg, account_key) orelse return false;
    if (registry.rolloutSignaturesEqual(reg.accounts.items[idx].last_local_rollout, signature)) return false;

    const snapshot = latest.usage orelse return false;
    if (registry.rateLimitSnapshotsEqual(reg.accounts.items[idx].last_usage, snapshot)) return false;

    registry.updateUsage(allocator, reg, account_key, snapshot);
    try registry.setAccountLastLocalRollout(allocator, &reg.accounts.items[idx], latest.path, event_timestamp_ms);
    return true;
}

pub fn refreshActiveUsageForDisplay(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
) !?registry.RateLimitSnapshot {
    return refreshActiveUsageWithApiFetcher(allocator, gemini_home, reg, usage_api.fetchActiveUsage);
}

pub fn refreshActiveUsageForDisplayWithApiFetcher(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    api_fetcher: anytype,
) !?registry.RateLimitSnapshot {
    return refreshActiveUsageWithApiFetcher(allocator, gemini_home, reg, api_fetcher);
}

pub fn refreshActiveUsageForDisplayWithApiFetchersWithPoolInit(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    api_fetcher: anytype,
) !?registry.RateLimitSnapshot {
    _ = api_fetcher;
    return refreshActiveUsageWithApiFetcher(allocator, gemini_home, reg, usage_api.fetchActiveUsage);
}

pub fn ForegroundUsageOutcome = enum { unchanged, updated };

pub const ForegroundUsageRefreshState = struct {
    rollout_scan_cache: ?sessions.RolloutScanCache,
    last_api_refresh_at_ns: i128,
};

pub fn refreshForegroundUsage(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
) !ForegroundUsageOutcome {
    if (reg.api.usage) {
        if (refreshActiveUsageWithApiFetcher(allocator, gemini_home, reg, usage_api.fetchActiveUsage)) {
            return .updated;
        }
    }
    if (refreshActiveUsageFromSessions(allocator, gemini_home, reg, &ForegroundUsageRefreshState{
        .rollout_scan_cache = null,
        .last_api_refresh_at_ns = 0,
    })) {
        return .updated;
    }
    return .unchanged;
}

pub fn refreshForegroundUsageWithFetcher(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    api_fetcher: anytype,
) !ForegroundUsageOutcome {
    if (refreshActiveUsageWithApiFetcher(allocator, gemini_home, reg, api_fetcher)) {
        return .updated;
    }
    if (refreshActiveUsageFromSessions(allocator, gemini_home, reg, &ForegroundUsageRefreshState{
        .rollout_scan_cache = null,
        .last_api_refresh_at_ns = 0,
    })) {
        return .updated;
    }
    return .unchanged;
}

pub fn refreshForegroundUsageWithFetchersWithPoolInit(
    allocator: std.mem.Allocator,
    gemini_home: []const u8,
    reg: *registry.Registry,
    api_fetcher: anytype,
) !ForegroundUsageOutcome {
    _ = api_fetcher;
    return refreshForegroundUsage(allocator, gemini_home, reg);
}

const std = @import("std");
const cli = @import("../cli/root.zig");
const auto = @import("../auto/root.zig");
const io_util = @import("../core/io_util.zig");
const registry = @import("../registry/root.zig");

pub fn handleConfig(allocator: std.mem.Allocator, gemini_home: []const u8, opts: cli.types.ConfigOptions) !void {
    switch (opts) {
        .auto_switch => |auto_opts| try auto.handleAutoCommand(allocator, gemini_home, auto_opts),
        .api => |action| try auto.handleApiCommand(allocator, gemini_home, action),
        .live => |live_opts| try handleLiveCommand(allocator, gemini_home, live_opts),
    }
}

fn handleLiveCommand(allocator: std.mem.Allocator, gemini_home: []const u8, opts: cli.types.LiveOptions) !void {
    var reg = try registry.loadRegistry(allocator, gemini_home);
    defer reg.deinit(allocator);
    reg.live.interval_seconds = opts.interval_seconds;
    try registry.saveRegistry(allocator, gemini_home, &reg);

    var stdout: io_util.Stdout = undefined;
    stdout.init();
    const out = stdout.out();
    try out.print("Live refresh interval: {d}s\n", .{opts.interval_seconds});
    try out.flush();
}

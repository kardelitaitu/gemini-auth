const std = @import("std");
const app_runtime = @import("../core/runtime.zig");
const types = @import("types.zig");
const output = @import("output.zig");
const style = @import("style.zig");

pub fn geminiLoginArgs(opts: types.LoginOptions) []const []const u8 {
    return if (opts.device_auth)
        &[_][]const u8{ "gemini", "login", "--device-auth" }
    else
        &[_][]const u8{ "gemini", "login" };
}

fn ensureGeminiLoginSucceeded(term: std.process.Child.Term) !void {
    switch (term) {
        .exited => |code| {
            if (code == 0) return;
            return error.GeminiLoginFailed;
        },
        else => return error.GeminiLoginFailed,
    }
}

fn writeGeminiLoginLaunchFailureHint(err_name: []const u8) !void {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stderr().writer(app_runtime.io(), &buffer);
    const out = &writer.interface;
    try output.writeGeminiLoginLaunchFailureHintTo(out, err_name, style.stderrColorEnabled());
    try out.flush();
}

pub fn runGeminiLogin(opts: types.LoginOptions) !void {
    var child = std.process.spawn(app_runtime.io(), .{
        .argv = geminiLoginArgs(opts),
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        writeGeminiLoginLaunchFailureHint(@errorName(err)) catch {};
        return err;
    };
    const term = child.wait(app_runtime.io()) catch |err| {
        writeGeminiLoginLaunchFailureHint(@errorName(err)) catch {};
        return err;
    };
    try ensureGeminiLoginSucceeded(term);
}

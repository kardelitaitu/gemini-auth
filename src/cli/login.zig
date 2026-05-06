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
    _ = opts; // Not used for Gemini OAuth instructions

    var buffer: [2048]u8 = undefined;
    var writer = std.Io.File.stderr().writer(app_runtime.io(), &buffer);
    const out = &writer.interface;

    try out.writeAll("Gemini CLI authentication requires Google OAuth2 setup.\n\n");
    try out.writeAll("To authenticate with Gemini CLI:\n\n");
    try out.writeAll("1. Visit: https://accounts.google.com/o/oauth2/auth?...\n");
    try out.writeAll("2. Sign in with your Google account\n");
    try out.writeAll("3. Grant permissions for Gemini API access\n");
    try out.writeAll("4. Copy the authorization code\n");
    try out.writeAll("5. Save the resulting tokens to ~/.gemini/oauth_creds.json\n\n");
    try out.writeAll("Alternatively, run the Gemini CLI directly if installed:\n");
    try out.writeAll("  gemini login\n\n");
    try out.writeAll("Then use 'gemini-auth import ~/.gemini/oauth_creds.json' to import the tokens.\n");

    try out.flush();
    return error.GeminiLoginNotImplemented;
}

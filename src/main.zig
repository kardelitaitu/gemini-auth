const std = @import("std");
const gemini_auth = @import("root.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    return gemini_auth.workflows.main(init);
}

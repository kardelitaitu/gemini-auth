const std = @import("std");
const gemini_auth = @import("gemini_auth");

test {
    std.testing.refAllDecls(gemini_auth);
}

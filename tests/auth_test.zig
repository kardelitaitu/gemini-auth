const std = @import("std");
const app_runtime = @import("gemini_auth").core.runtime;
const auth = @import("gemini_auth").auth;
const fixtures = @import("support/fixtures.zig");

test "parse Gemini OAuth2 auth info from oauth_creds.json" {
    const gpa = std.testing.allocator;
    const auth_path = try fixtures.geminiAuthPathAlloc(gpa);
    defer gpa.free(auth_path);

    const info = try auth.parseAuthInfo(gpa, auth_path);
    defer info.deinit(gpa);

    // Verify basic structure
    try std.testing.expect(info.access_token != null);
    try std.testing.expect(info.refresh_token != null);
    try std.testing.expect(info.id_token != null);
    try std.testing.expect(info.expiry_date != null);

    // Verify JWT extraction
    try std.testing.expect(info.email != null);
    try std.testing.expect(std.mem.eql(u8, info.email.?, "adikaradwiatmaja@gmail.com"));
    try std.testing.expect(info.google_user_id != null);
    try std.testing.expect(info.name != null);
    try std.testing.expect(std.mem.eql(u8, info.name.?, "Adikara Dwi Atmaja"));
}

test "parse auth info handles missing file" {
    const gpa = std.testing.allocator;

    try std.testing.expectError(
        error.FileNotFound,
        auth.parseAuthInfo(gpa, "nonexistent.json"),
    );
}

test "parse auth info handles invalid JSON" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "invalid.json",
        .data = "not json",
    });

    const auth_path = try tmp.dir.realpathAlloc(gpa, "invalid.json");
    defer gpa.free(auth_path);

    try std.testing.expectError(
        error.InvalidJson,
        auth.parseAuthInfo(gpa, auth_path),
    );
}

test "parse auth info handles missing access token" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create JSON without access_token
    const json = 
        \\{
        \\  "refresh_token": "test-refresh",
        \\  "id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6IjE5Y2FhZWNkZThmNDg1ZThmNTkzOGY0OGFiYTBjZTdhMzU4MWYwMjciLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20iLCJhenAiOiI2NjgxMjU4MDkzOTUtb284ZnQyb3Bkcm5wOWUzYXFmNmF2M2hoYjEzNWouYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJhdWQiOiI2NjgxMjU4MDkzOTUtb284ZnQyb3Bkcm5wOWUzYXFmNmF2M2hoYjEzNWouYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdwiOiIxMDk5MDAwMTMzNjc5MTQzNDI4MTUiLCJlbWFpbCI6ImFkaWthcmFkd2lhdG1hamFAZ21haWwuY29tIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsImF0X2hhc2giOiJScEVkU1JLOTcxSk52aDdra1RrNllNMVlEut1idDQ2TFgRkUxN1kxN1l5V0xVVlRN2lQIiwibmFtZSI6IkFkaWthcmFkd2lhdG1hamEiLCJwaWN0dXJlIjoiYGh0dHBzOi8vbGgMy5nb29nbGV1c2VyY29udGVudC5jb20vL2Evcm9weC8z2MGViqvL2JhjYTM2WSIsImdpdmVuX25hbWUiOiJBZGlrYXJhIiwiZmFtaWx5bmFtZSI6IkF0bWFqYSIsInBpY3R1cmUiOiJodHRwczovL2xoMy5nb29nbGV1c2VyY29udGVudC5jb20vL2Evcm9weC8z2MGViqvL2JhjYTM2WSJ9.sVD1PAPRXlsjxim2Say_TTRxrv9btQ-11JvtsOXVpm3UXcUu2cjJKuDVCAvxqxZ5WlI2-mfUrbmIA91GF73bbUTyvxZwRkNK20CJTHi4981X-H8cHVctMPR0j899prYY4pa779_v4V7JovfvF48DGukuJvMZr0S8OVjX17kBikaJ6l2qspFybQ7Wl9V7BXeXg9f-nC3tmSogWcJoocWkYl5qsbBozIB7Vjs7G7vTWJV7GAs03hMVA4f1iQTSOqiLxgmD2HE_Fpzl6Nba1h1zyZtVMW7p8u5PezMvlURiVX025ujQ2SuBhR3R9dyAUdK-zhfSd78wkJ5mqDcHI6zoVA"
    ;
    try tmp.dir.writeFile(.{
        .sub_path = "missing_access.json",
        .data = json,
    });

    const auth_path = try tmp.dir.realpathAlloc(gpa, "missing_access.json");
    defer gpa.free(auth_path);

    const info = try auth.parseAuthInfo(gpa, auth_path);
    defer info.deinit(gpa);

    try std.testing.expect(info.access_token == null);
    try std.testing.expect(info.refresh_token != null);
    try std.testing.expect(info.id_token != null);
}

test "parse auth info handles missing id_token" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create JSON without id_token
    const json = 
        \\{
        \\  "access_token": "test-access",
        \\  "refresh_token": "test-refresh",
        \\  "expiry_date": 1777639046350
        \\}
    ;
    try tmp.dir.writeFile(.{
        .sub_path = "missing_id.json",
        .data = json,
    });

    const auth_path = try tmp.dir.realpathAlloc(gpa, "missing_id.json");
    defer gpa.free(auth_path);

    const info = try auth.parseAuthInfo(gpa, auth_path);
    defer info.deinit(gpa);

    try std.testing.expect(info.access_token != null);
    try std.testing.expect(info.id_token == null);
    try std.testing.expect(info.email == null);
    try std.testing.expect(info.google_user_id == null);
    try std.testing.expect(info.name == null);
}

test "parse auth info handles invalid id_token" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create JSON with invalid id_token
    const json = 
        \\{
        \\  "access_token": "test-access",
        \\  "refresh_token": "test-refresh",
        \\  "id_token": "invalid-jwt",
        \\  "expiry_date": 1777639046350
        \\}
    ;
    try tmp.dir.writeFile(.{
        .sub_path = "invalid_id.json",
        .data = json,
    });

    const auth_path = try tmp.dir.realpathAlloc(gpa, "invalid_id.json");
    defer gpa.free(auth_path);

    const info = try auth.parseAuthInfo(gpa, auth_path);
    defer info.deinit(gpa);

    try std.testing.expect(info.access_token != null);
    try std.testing.expect(info.id_token != null);
    // Invalid JWT should result in null fields
    try std.testing.expect(info.email == null);
    try std.testing.expect(info.google_user_id == null);
}

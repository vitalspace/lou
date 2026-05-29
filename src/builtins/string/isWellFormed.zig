const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn IsWellFormed(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .boolean = true } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .boolean = true } },
    };
    var i: usize = 0;
    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
            return .{ .value = .{ .boolean = false } };
        };
        if (i + byte_len > s.len) return .{ .value = .{ .boolean = false } };
        if (byte_len == 3) {
            const cp = std.unicode.utf8Decode(s[i .. i + byte_len]) catch {
                return .{ .value = .{ .boolean = false } };
            };
            if (cp >= 0xD800 and cp <= 0xDFFF) return .{ .value = .{ .boolean = false } };
        }
        i += byte_len;
    }
    return .{ .value = .{ .boolean = true } };
}

const testing = std.testing;

test "isWellFormed normal string" {
    var args = [_]Types.Value{ .{ .string = "hello" } };
    const result = IsWellFormed(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "isWellFormed empty string" {
    var args = [_]Types.Value{ .{ .string = "" } };
    const result = IsWellFormed(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "isWellFormed lone surrogate high" {
    // \uD800 in UTF-8 is: ED A0 80
    var args = [_]Types.Value{ .{ .string = "\xED\xA0\x80" } };
    const result = IsWellFormed(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "isWellFormed lone surrogate low" {
    // \uDC00 in UTF-8 is: ED B0 80
    var args = [_]Types.Value{ .{ .string = "\xED\xB0\x80" } };
    const result = IsWellFormed(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "isWellFormed valid surrogate pair (emoji)" {
    // U+1F600 = F0 9F 98 80 in UTF-8
    var args = [_]Types.Value{ .{ .string = "\xF0\x9F\x98\x80" } };
    const result = IsWellFormed(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "isWellFormed non-string returns true" {
    var args = [_]Types.Value{ .{ .integer = 42 } };
    const result = IsWellFormed(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "isWellFormed no args returns true" {
    const result = IsWellFormed(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "isWellFormed lone surrogate in middle" {
    // "a\uDC00b" in UTF-8
    var args = [_]Types.Value{ .{ .string = "a\xED\xB0\x80" ++ "b" } };
    const result = IsWellFormed(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

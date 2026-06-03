const std = @import("std");
const Types = @import("../../types/types.zig");
const utils = @import("string_utils.zig");

pub fn StartsWith(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .boolean = false } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .boolean = false } },
    };
    if (args.len < 2) return .{ .value = .{ .boolean = false } };
    const searchString = switch (args[1]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .boolean = false } },
    };
    const position: i64 = if (args.len < 3) 0 else switch (args[2]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => 0,
        .null => 0,
        else => 0,
    };

    // Convert position from codepoint index to byte index
    const cp_len = utils.cpCount(s);
    const clamped_pos: i64 = if (position < 0) 0 else if (position > cp_len) cp_len else position;
    const byte_start = utils.cpToByte(s, clamped_pos);

    if (searchString.len == 0) return .{ .value = .{ .boolean = true } };
    if (byte_start > s.len) return .{ .value = .{ .boolean = false } };
    if (byte_start + searchString.len > s.len) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = std.mem.eql(u8, s[byte_start .. byte_start + searchString.len], searchString) } };
}

const testing = std.testing;

test "startsWith positive" {
    var args = [_]Types.Value{ .{ .string = "Saturday night plans" }, .{ .string = "Sat" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith negative" {
    var args = [_]Types.Value{ .{ .string = "Saturday night plans" }, .{ .string = "Sun" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith empty searchString" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith position shifts start" {
    var args = [_]Types.Value{ .{ .string = "Saturday night plans" }, .{ .string = "Sat" }, .{ .integer = 3 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith position finds later match" {
    var args = [_]Types.Value{ .{ .string = "Saturday night plans" }, .{ .string = "day" }, .{ .integer = 5 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith position at start of word" {
    var args = [_]Types.Value{ .{ .string = "Saturday night plans" }, .{ .string = "night" }, .{ .integer = 9 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith case sensitive" {
    var args = [_]Types.Value{ .{ .string = "Hello" }, .{ .string = "hello" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith position beyond length" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "h" }, .{ .integer = 10 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith negative position treated as 0" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "hello" }, .{ .integer = -1 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith non-string this returns false" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "4" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith no args returns false" {
    const result = StartsWith(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith non-string searchString returns false" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 42 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith multi-byte UTF-8" {
    var args = [_]Types.Value{ .{ .string = "ñoño" }, .{ .string = "ño" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith multi-byte UTF-8 with position" {
    var args = [_]Types.Value{ .{ .string = "ñoño" }, .{ .string = "ño" }, .{ .integer = 2 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith 4-byte emoji" {
    var args = [_]Types.Value{ .{ .string = "\xF0\x9F\x98\x80 mundo" }, .{ .string = "\xF0\x9F\x98\x80" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

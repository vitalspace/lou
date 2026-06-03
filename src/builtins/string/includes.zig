const std = @import("std");
const Types = @import("../../types/types.zig");
const utils = @import("string_utils.zig");

pub fn Includes(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
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
    if (byte_start >= s.len) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = std.mem.indexOf(u8, s[byte_start..], searchString) != null } };
}

const testing = std.testing;

test "includes finds substring" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "world" } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "includes not found" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "xyz" } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "includes empty searchString" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "includes with position" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "world" }, .{ .integer = 6 } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "includes position too late" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "world" }, .{ .integer = 7 } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "includes negative position treated as 0" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "hello" }, .{ .integer = -1 } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "includes case sensitive" {
    var args = [_]Types.Value{ .{ .string = "Hello World" }, .{ .string = "world" } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "includes position beyond length" {
    var args = [_]Types.Value{ .{ .string = "hi" }, .{ .string = "hi" }, .{ .integer = 5 } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "includes non-string this returns false" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "2" } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "includes no args returns false" {
    const result = Includes(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "includes multi-byte UTF-8" {
    var args = [_]Types.Value{ .{ .string = "ñoño" }, .{ .string = "ñ" } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "includes multi-byte UTF-8 with position" {
    // position=1 starts from cp1 ("o"), "oño" DOES include "ñ"
    var args = [_]Types.Value{ .{ .string = "ñoño" }, .{ .string = "ñ" }, .{ .integer = 1 } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "includes 4-byte emoji" {
    var args = [_]Types.Value{ .{ .string = "hola \xF0\x9F\x98\x80 mundo" }, .{ .string = "\xF0\x9F\x98\x80" } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

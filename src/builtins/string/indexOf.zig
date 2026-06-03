const std = @import("std");
const Types = @import("../../types/types.zig");
const utils = @import("string_utils.zig");

pub fn IndexOf(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .integer = -1 } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .integer = -1 } },
    };
    if (args.len < 2) return .{ .value = .{ .integer = -1 } };
    const searchString = switch (args[1]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .integer = -1 } },
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

    if (searchString.len == 0) return .{ .value = .{ .integer = clamped_pos } };
    if (byte_start > s.len) return .{ .value = .{ .integer = -1 } };
    if (std.mem.indexOf(u8, s[byte_start..], searchString)) |match_byte| {
        // Convert the byte-level match offset back to a codepoint index
        return .{ .value = .{ .integer = clamped_pos + utils.byteToCp(s[byte_start..], match_byte) } };
    }
    return .{ .value = .{ .integer = -1 } };
}

const testing = std.testing;

test "indexOf finds substring" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "world" } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 6), result.value.integer);
}

test "indexOf not found returns -1" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "xyz" } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "indexOf empty string returns position" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" }, .{ .integer = 2 } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 2), result.value.integer);
}

test "indexOf empty string default position 0" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "indexOf with position" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "o" }, .{ .integer = 5 } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 7), result.value.integer);
}

test "indexOf case sensitive" {
    var args = [_]Types.Value{ .{ .string = "Hello" }, .{ .string = "hello" } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "indexOf position beyond length" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "h" }, .{ .integer = 10 } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "indexOf negative position treated as 0" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "hello" }, .{ .integer = -1 } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "indexOf first occurrence" {
    var args = [_]Types.Value{ .{ .string = "banana" }, .{ .string = "na" } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 2), result.value.integer);
}

test "indexOf non-string this returns -1" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "2" } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "indexOf no args returns -1" {
    const result = IndexOf(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "indexOf empty string with position beyond len clamped" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" }, .{ .integer = 99 } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 5), result.value.integer);
}

test "indexOf multi-byte UTF-8" {
    // "ñoño" has codepoints: ñ(2 bytes), o(1), ñ(2), o(1) = 6 bytes, 4 codepoints
    var args = [_]Types.Value{ .{ .string = "ñoño" }, .{ .string = "o" } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 1), result.value.integer);
}

test "indexOf multi-byte UTF-8 with position" {
    var args = [_]Types.Value{ .{ .string = "ñoño" }, .{ .string = "o" }, .{ .integer = 2 } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 3), result.value.integer);
}

test "indexOf 4-byte emoji" {
    // "hola 😀 mundo" — 😀 is at codepoint index 5
    var args = [_]Types.Value{ .{ .string = "hola \xF0\x9F\x98\x80 mundo" }, .{ .string = "\xF0\x9F\x98\x80" } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 5), result.value.integer);
}

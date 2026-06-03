const std = @import("std");
const Types = @import("../../types/types.zig");
const utils = @import("string_utils.zig");

pub fn LastIndexOf(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
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
    const cp_len = utils.cpCount(s);
    const raw_position = if (args.len < 3) cp_len else switch (args[2]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => cp_len,
        .null => cp_len,
        else => cp_len,
    };
    const pos: i64 = if (raw_position < 0) 0 else if (raw_position > cp_len) cp_len else raw_position;

    // Convert codepoint position to byte index
    const byte_end = utils.cpToByte(s, pos);

    if (searchString.len == 0) return .{ .value = .{ .integer = pos } };
    if (searchString.len > s.len) return .{ .value = .{ .integer = -1 } };

    // Search backwards from byte_end
    var start: usize = byte_end;
    if (start + searchString.len > s.len) {
        if (s.len >= searchString.len) {
            start = s.len - searchString.len;
        } else {
            return .{ .value = .{ .integer = -1 } };
        }
    }

    var i: usize = start + 1;
    while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, s[i .. i + searchString.len], searchString)) {
            // Convert byte offset back to codepoint index
            return .{ .value = .{ .integer = utils.byteToCp(s, i) } };
        }
    }
    return .{ .value = .{ .integer = -1 } };
}

const testing = std.testing;

test "lastIndexOf finds last occurrence" {
    var args = [_]Types.Value{ .{ .string = "hello world hello" }, .{ .string = "hello" } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 12), result.value.integer);
}

test "lastIndexOf not found returns -1" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "xyz" } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "lastIndexOf empty string returns position" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" }, .{ .integer = 2 } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 2), result.value.integer);
}

test "lastIndexOf empty string no position" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 5), result.value.integer);
}

test "lastIndexOf with position limits search" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "o" }, .{ .integer = 4 } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 4), result.value.integer);
}

test "lastIndexOf case sensitive" {
    var args = [_]Types.Value{ .{ .string = "Hello" }, .{ .string = "hello" } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "lastIndexOf negative position treated as 0" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "hello" }, .{ .integer = -1 } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "lastIndexOf position beyond length" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "hello" }, .{ .integer = 99 } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "lastIndexOf single char" {
    var args = [_]Types.Value{ .{ .string = "banana" }, .{ .string = "a" } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 5), result.value.integer);
}

test "lastIndexOf non-string this returns -1" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "2" } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "lastIndexOf no args returns -1" {
    const result = LastIndexOf(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "lastIndexOf duplicate last occurrence" {
    var args = [_]Types.Value{ .{ .string = "abcabc" }, .{ .string = "abc" } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 3), result.value.integer);
}

test "lastIndexOf multi-byte UTF-8" {
    // "ñoño" — last "o" is at codepoint 3
    var args = [_]Types.Value{ .{ .string = "ñoño" }, .{ .string = "o" } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 3), result.value.integer);
}

test "lastIndexOf multi-byte UTF-8 with position" {
    // "ñoño" — searching backward from codepoint 2 (second ñ), last "o" before that is at cp 1
    var args = [_]Types.Value{ .{ .string = "ñoño" }, .{ .string = "o" }, .{ .integer = 2 } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 1), result.value.integer);
}

test "lastIndexOf 4-byte emoji" {
    // "hola \xF0\x9F\x98\x80 mundo \xF0\x9F\x98\x80" — last emoji at cp 13
    // h(0) o(1) l(2) a(3) ' '(4) 😀(5) ' '(6) m(7) u(8) n(9) d(10) o(11) ' '(12) 😀(13)
    var args = [_]Types.Value{ .{ .string = "hola \xF0\x9F\x98\x80 mundo \xF0\x9F\x98\x80" }, .{ .string = "\xF0\x9F\x98\x80" } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 13), result.value.integer);
}

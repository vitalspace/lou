const std = @import("std");
const Types = @import("../../types/types.zig");
const utils = @import("string_utils.zig");

pub fn EndsWith(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
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
    const cp_len = utils.cpCount(s);
    const endPosition: i64 = if (args.len < 3) cp_len else switch (args[2]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => cp_len,
        .null => cp_len,
        else => cp_len,
    };

    // Convert endPosition from codepoint index to byte index
    if (searchString.len == 0) return .{ .value = .{ .boolean = true } };
    if (endPosition <= 0) return .{ .value = .{ .boolean = false } };
    const clamped: i64 = if (endPosition > cp_len) cp_len else endPosition;
    var byte_end = utils.cpToByte(s, clamped);
    if (byte_end > s.len) byte_end = s.len;
    if (byte_end < searchString.len) return .{ .value = .{ .boolean = false } };
    const start = byte_end - searchString.len;
    return .{ .value = .{ .boolean = std.mem.eql(u8, s[start..byte_end], searchString) } };
}

const testing = std.testing;

test "endsWith positive" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "world" } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "endsWith negative" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "hello" } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "endsWith empty searchString" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "endsWith endPosition limits scope" {
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "world" }, .{ .integer = 5 } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "endsWith endPosition zero returns false" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "hello" }, .{ .integer = 0 } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "endsWith case sensitive" {
    var args = [_]Types.Value{ .{ .string = "Hello" }, .{ .string = "hello" } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "endsWith endPosition matching substring" {
    var args = [_]Types.Value{ .{ .string = "to be or not" }, .{ .string = "to be" }, .{ .integer = 5 } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "endsWith non-string this returns false" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "2" } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "endsWith no args returns false" {
    const result = EndsWith(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "endsWith multi-byte UTF-8" {
    var args = [_]Types.Value{ .{ .string = "ñoño" }, .{ .string = "ño" } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "endsWith multi-byte UTF-8 with position" {
    // endPosition=3 considers first 3 codepoints: "ñoñ" — does NOT end with "o"
    var args = [_]Types.Value{ .{ .string = "ñoño" }, .{ .string = "o" }, .{ .integer = 3 } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "endsWith 4-byte emoji" {
    var args = [_]Types.Value{ .{ .string = "hola \xF0\x9F\x98\x80" }, .{ .string = "\xF0\x9F\x98\x80" } };
    const result = EndsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

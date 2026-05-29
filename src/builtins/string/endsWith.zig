const std = @import("std");
const Types = @import("../../types/types.zig");

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
    const endPosition: i64 = if (args.len < 3) @as(i64, @intCast(s.len)) else switch (args[2]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => @as(i64, @intCast(s.len)),
        .null => @as(i64, @intCast(s.len)),
        else => @as(i64, @intCast(s.len)),
    };
    if (searchString.len == 0) return .{ .value = .{ .boolean = true } };
    if (endPosition <= 0) return .{ .value = .{ .boolean = false } };
    var end = @as(usize, @intCast(endPosition));
    if (end > s.len) end = s.len;
    if (end < searchString.len) return .{ .value = .{ .boolean = false } };
    const start = end - searchString.len;
    return .{ .value = .{ .boolean = std.mem.eql(u8, s[start..end], searchString) } };
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

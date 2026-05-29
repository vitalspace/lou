const std = @import("std");
const Types = @import("../../types/types.zig");

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
    if (searchString.len == 0) return .{ .value = .{ .boolean = true } };
    const pos: usize = if (position < 0) 0 else @as(usize, @intCast(position));
    if (pos >= s.len) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = std.mem.indexOf(u8, s[pos..], searchString) != null } };
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

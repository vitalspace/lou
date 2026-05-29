const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn LocaleCompare(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2) return .{ .value = .{ .integer = 0 } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .integer = 0 } },
    };
    const compareString = switch (args[1]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .integer = 0 } },
    };
    if (std.mem.eql(u8, s, compareString)) return .{ .value = .{ .integer = 0 } };
    const order = std.mem.order(u8, s, compareString);
    return .{ .value = .{ .integer = if (order == .lt) -1 else 1 } };
}

const testing = std.testing;

test "localeCompare equal strings" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "hello" } };
    const result = LocaleCompare(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "localeCompare less than" {
    var args = [_]Types.Value{ .{ .string = "apple" }, .{ .string = "banana" } };
    const result = LocaleCompare(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.integer < 0);
}

test "localeCompare greater than" {
    var args = [_]Types.Value{ .{ .string = "banana" }, .{ .string = "apple" } };
    const result = LocaleCompare(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.integer > 0);
}

test "localeCompare case sensitive" {
    var args = [_]Types.Value{ .{ .string = "Hello" }, .{ .string = "hello" } };
    const result = LocaleCompare(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.integer != 0);
}

test "localeCompare empty strings" {
    var args = [_]Types.Value{ .{ .string = "" }, .{ .string = "" } };
    const result = LocaleCompare(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "localeCompare non-string this returns 0" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "hello" } };
    const result = LocaleCompare(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "localeCompare non-string arg returns 0" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 42 } };
    const result = LocaleCompare(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "localeCompare less than shorter prefix" {
    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .string = "abcd" } };
    const result = LocaleCompare(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.integer < 0);
}

test "localeCompare greater than longer prefix" {
    var args = [_]Types.Value{ .{ .string = "abcd" }, .{ .string = "abc" } };
    const result = LocaleCompare(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.integer > 0);
}

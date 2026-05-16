const std = @import("std");
const Types = @import("../../types/types.zig");
const testing = std.testing;

pub fn Abs(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len != 1) return .{ .value = .{ .float = 0.0 } };
    return switch (args[0]) {
        .float => |f| .{ .value = .{ .float = @abs(f) } },
        .integer => |i| .{ .value = if (i < 0) .{ .integer = -i } else .{ .integer = i } },
        else => .{ .value = .{ .float = 0.0 } },
    };
}

test "abs positive integer" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = Abs(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expect(result.value.integer == 42);
}

test "abs negative integer" {
    var args = [_]Types.Value{.{ .integer = -42 }};
    const result = Abs(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expect(result.value.integer == 42);
}

test "abs positive float" {
    var args = [_]Types.Value{.{ .float = 3.14 }};
    const result = Abs(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .float);
    try testing.expect(result.value.float == 3.14);
}

test "abs negative float" {
    var args = [_]Types.Value{.{ .float = -2.5 }};
    const result = Abs(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .float);
    try testing.expect(result.value.float == 2.5);
}

test "abs zero" {
    var args = [_]Types.Value{.{ .integer = 0 }};
    const result = Abs(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expect(result.value.integer == 0);
}

test "abs no args returns 0.0" {
    const result = Abs(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);

    try testing.expect(result.value == .float);
    try testing.expect(result.value.float == 0.0);
}

test "abs non-number returns 0.0" {
    var args = [_]Types.Value{.{ .string = "hello" }};
    const result = Abs(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .float);
    try testing.expect(result.value.float == 0.0);
}

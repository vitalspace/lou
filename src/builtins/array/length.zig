const std = @import("std");

const ast = @import("../../ast.zig");
const Types = @import("../../types/types.zig");

pub fn Length(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    if (args.len != 1) {
        return .{ .value = .{ .integer = 0 } };
    }

    const array_val = args[0];
    if (array_val != .array) {
        return .{ .value = .{ .integer = 0 } };
    }

    return .{ .value = .{ .integer = @intCast(array_val.array.elements.items.len) } };
}

test "legth empty array" {
    const array = try ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = Length(&args, undefined);
    try std.testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "length array with 3 elements" {
    const array = try ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .float = 1.0 });
    try array.elements.append(array.allocator, .{ .float = 2.0 });
    try array.elements.append(array.allocator, .{ .string = "hello" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Length(&args, undefined);
    try std.testing.expectEqual(@as(i64, 3), result.value.integer);
}

test "length no args returns 0" {
    const result = Length(&[_]Types.Value{}, undefined);
    try std.testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "length too many args returns 0" {
    var args = [_]Types.Value{ .{ .float = 1.0 }, .{ .float = 2.0 } };
    const result = Length(&args, undefined);
    try std.testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "length non-array number returns 0" {
    var args = [_]Types.Value{.{ .float = 42.0 }};
    const result = Length(&args, undefined);
    try std.testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "length non-array string returns 0" {
    var args = [_]Types.Value{.{ .string = "not an array" }};
    const result = Length(&args, undefined);
    try std.testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "length non-array boolean returns 0" {
    var args = [_]Types.Value{.{ .boolean = true }};
    const result = Length(&args, undefined);
    try std.testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "length single element array" {
    const array = try ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .boolean = true });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Length(&args, undefined);
    try std.testing.expectEqual(@as(i64, 1), result.value.integer);
}

test "length large array" {
    const array = try ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try array.elements.append(array.allocator, .{ .float = @floatFromInt(i) });
    }

    var args = [_]Types.Value{.{ .array = array }};
    const result = Length(&args, undefined);
    try std.testing.expectEqual(@as(i64, 100), result.value.integer);
}

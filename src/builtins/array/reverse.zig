const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn Reverse(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    if (args.len != 1) {
        return .{ .value = .{ .void = {} } };
    }

    const array_val = args[0];
    if (array_val != .array) {
        return .{ .value = .{ .void = {} } };
    }

    const arr = array_val.array;
    const items = arr.elements.items;

    var i: usize = 0;
    while (i < items.len / 2) : (i += 1) {
        const j = items.len - 1 - i;
        const tmp = items[i];
        items[i] = items[j];
        items[j] = tmp;
    }

    return .{ .value = .{ .array = arr } };
}

const testing = std.testing;

test "reverse reverses array of strings" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .string = "one" });
    try array.elements.append(array.allocator, .{ .string = "two" });
    try array.elements.append(array.allocator, .{ .string = "three" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Reverse(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 3), array.elements.items.len);
    try testing.expectEqualSlices(u8, "three", array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "two", array.elements.items[1].string);
    try testing.expectEqualSlices(u8, "one", array.elements.items[2].string);
}

test "reverse returns the same array" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });
    try array.elements.append(array.allocator, .{ .integer = 2 });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Reverse(&args, undefined);

    try testing.expect(result.value.array == array);
}

test "reverse reverses numbers" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });
    try array.elements.append(array.allocator, .{ .integer = 2 });
    try array.elements.append(array.allocator, .{ .integer = 3 });
    try array.elements.append(array.allocator, .{ .integer = 4 });
    try array.elements.append(array.allocator, .{ .integer = 5 });

    var args = [_]Types.Value{.{ .array = array }};
    _ = Reverse(&args, undefined);

    try testing.expectEqual(@as(i64, 5), array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 4), array.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 3), array.elements.items[2].integer);
    try testing.expectEqual(@as(i64, 2), array.elements.items[3].integer);
    try testing.expectEqual(@as(i64, 1), array.elements.items[4].integer);
}

test "reverse single element does nothing" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 42 });

    var args = [_]Types.Value{.{ .array = array }};
    _ = Reverse(&args, undefined);

    try testing.expectEqual(@as(usize, 1), array.elements.items.len);
    try testing.expectEqual(@as(i64, 42), array.elements.items[0].integer);
}

test "reverse empty array" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = Reverse(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 0), array.elements.items.len);
}

test "reverse mixed types" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });
    try array.elements.append(array.allocator, .{ .string = "hello" });
    try array.elements.append(array.allocator, .{ .boolean = true });

    var args = [_]Types.Value{.{ .array = array }};
    _ = Reverse(&args, undefined);

    try testing.expectEqual(true, array.elements.items[0].boolean);
    try testing.expectEqualSlices(u8, "hello", array.elements.items[1].string);
    try testing.expectEqual(@as(i64, 1), array.elements.items[2].integer);
}

test "reverse no args returns void" {
    const result = Reverse(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "reverse non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = Reverse(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

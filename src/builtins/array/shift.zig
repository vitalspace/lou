const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn Shift(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    if (args.len != 1) {
        return .{ .value = .{ .void = {} } };
    }

    const array_val = args[0];
    if (array_val != .array) {
        return .{ .value = .{ .void = {} } };
    }

    const arr = array_val.array;

    if (arr.elements.items.len == 0) {
        return .{ .value = .{ .void = {} } };
    }

    const first = arr.elements.items[0];
    const len = arr.elements.items.len;

    if (len > 1) {
        std.mem.copyForwards(Types.Value, arr.elements.items[0 .. len - 1], arr.elements.items[1..]);
    }
    _ = arr.elements.pop();

    return .{ .value = first };
}

const testing = std.testing;

test "shift returns first element" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });
    try array.elements.append(array.allocator, .{ .integer = 2 });
    try array.elements.append(array.allocator, .{ .integer = 3 });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Shift(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value.integer == 1);
}

test "shift reduces length" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });
    try array.elements.append(array.allocator, .{ .integer = 2 });

    var args = [_]Types.Value{.{ .array = array }};
    _ = Shift(&args, undefined);

    try testing.expectEqual(@as(usize, 1), array.elements.items.len);
    try testing.expectEqual(@as(i64, 2), array.elements.items[0].integer);
}

test "shift empty array returns undefined" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = Shift(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "shift no args returns undefined" {
    const result = Shift(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "shift non-array returns undefined" {
    var args = [_]Types.Value{.{ .float = 42.0 }};
    const result = Shift(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "shift returns string element" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .string = "hello" });
    try array.elements.append(array.allocator, .{ .string = "world" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Shift(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "hello", result.value.string);
}

test "shift single element makes array empty" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .float = 9.9 });

    var args = [_]Types.Value{.{ .array = array }};
    _ = Shift(&args, undefined);

    try testing.expectEqual(@as(usize, 0), array.elements.items.len);
}

test "shift shifts remaining elements left" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .string = "a" });
    try array.elements.append(array.allocator, .{ .string = "b" });
    try array.elements.append(array.allocator, .{ .string = "c" });
    try array.elements.append(array.allocator, .{ .string = "d" });

    var args = [_]Types.Value{.{ .array = array }};
    _ = Shift(&args, undefined); // removes "a"
    _ = Shift(&args, undefined); // removes "b"

    try testing.expectEqual(@as(usize, 2), array.elements.items.len);
    try testing.expectEqualSlices(u8, "c", array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "d", array.elements.items[1].string);
}

test "shift mixed types" {
    const array = try Ast.ArrayObject.init(testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });
    try array.elements.append(array.allocator, .{ .string = "hello" });
    try array.elements.append(array.allocator, .{ .boolean = true });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Shift(&args, undefined);

    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 1), result.value.integer);
    try testing.expectEqual(@as(usize, 2), array.elements.items.len);
    try testing.expectEqualSlices(u8, "hello", array.elements.items[0].string);
}

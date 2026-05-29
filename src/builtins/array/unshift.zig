const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn Unshift(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    if (args.len < 2) return .{ .value = .{ .integer = 0 } };
    if (args[0] != .array) return .{ .value = .{ .integer = 0 } };

    const arr = args[0].array;
    const items_to_add = args[1..];
    const current_len = arr.elements.items.len;
    const new_len = current_len + items_to_add.len;

    arr.elements.ensureTotalCapacity(arr.allocator, new_len) catch {
        return .{ .value = .{ .integer = 0 } };
    };

    // extend the slice to new length
    arr.elements.items.len = new_len;

    // shift existing elements right
    var i: usize = current_len;
    while (i > 0) {
        i -= 1;
        arr.elements.items[i + items_to_add.len] = arr.elements.items[i];
    }

    // insert new items at front
    for (items_to_add, 0..) |item, j| {
        arr.elements.items[j] = item;
    }

    return .{ .value = .{ .integer = @intCast(new_len) } };
}

const testing = std.testing;

test "unshift adds to front and returns length" {
    const allocator = testing.allocator;

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 4 }, .{ .integer = 5 } };
    const result = Unshift(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expect(result.value.integer == 5);
}

test "unshift modifies array in place" {
    const allocator = testing.allocator;

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 4 }, .{ .integer = 5 } };
    _ = Unshift(&args, undefined);

    try testing.expectEqual(@as(usize, 5), array.elements.items.len);
    try testing.expectEqual(@as(i64, 4), array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 5), array.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 1), array.elements.items[2].integer);
    try testing.expectEqual(@as(i64, 2), array.elements.items[3].integer);
    try testing.expectEqual(@as(i64, 3), array.elements.items[4].integer);
}

test "unshift single element" {
    const allocator = testing.allocator;

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "a" } };
    _ = Unshift(&args, undefined);

    try testing.expectEqual(@as(usize, 3), array.elements.items.len);
    try testing.expectEqualSlices(u8, "a", array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "b", array.elements.items[1].string);
    try testing.expectEqualSlices(u8, "c", array.elements.items[2].string);
}

test "unshift empty array" {
    const allocator = testing.allocator;

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 } };
    const result = Unshift(&args, undefined);

    try testing.expect(result.value.integer == 1);
    try testing.expectEqual(@as(usize, 1), array.elements.items.len);
    try testing.expectEqual(@as(i64, 1), array.elements.items[0].integer);
}

test "unshift no args returns 0" {
    const result = Unshift(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expect(result.value.integer == 0);
}

test "unshift non-array returns 0" {
    var args = [_]Types.Value{ .{ .float = 42.0 }, .{ .integer = 1 } };
    const result = Unshift(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expect(result.value.integer == 0);
}

test "unshift multiple types" {
    const allocator = testing.allocator;

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .boolean = true }, .{ .string = "a" } };
    _ = Unshift(&args, undefined);

    try testing.expectEqual(@as(usize, 4), array.elements.items.len);
    try testing.expectEqual(true, array.elements.items[0].boolean);
    try testing.expectEqualSlices(u8, "a", array.elements.items[1].string);
    try testing.expectEqual(@as(i64, 2), array.elements.items[2].integer);
    try testing.expectEqual(@as(i64, 3), array.elements.items[3].integer);
}

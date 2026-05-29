const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn Push(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    if (args.len < 2) {
        return .{ .value = .{ .integer = 0 } };
    }

    const array_val = args[0];
    if (array_val != .array) {
        return .{ .value = .{ .integer = 0 } };
    }

    const arr = array_val.array;
    const items_to_add = args[1..];
    const current_len = arr.elements.items.len;
    const new_len = current_len + items_to_add.len;

    arr.elements.ensureTotalCapacity(arr.allocator, new_len) catch {
        return .{ .value = .{ .integer = 0 } };
    };

    arr.elements.appendSliceAssumeCapacity(items_to_add);

    return .{ .value = .{ .integer = @intCast(new_len) } };
}

test "push one element returns new length" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 } };
    const result = Push(&args, undefined);
    try std.testing.expect(result == .value and result.value.integer == 2);
}

test "push multiple elements returns length" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 } };
    const result = Push(&args, undefined);
    try std.testing.expect(result == .value and result.value.integer == 3);
}

test "push actually adds element" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "new" } };
    _ = Push(&args, undefined);
    try std.testing.expectEqual(@as(usize, 1), array.elements.items.len);
    try std.testing.expectEqualSlices(u8, "new", array.elements.items[0].string);
}

test "push no args returns 0" {
    const result = Push(&[_]Types.Value{}, undefined);
    try std.testing.expect(result == .value and result.value.integer == 0);
}

test "push non-array returns 0" {
    var args = [_]Types.Value{ .{ .float = 42.0 }, .{ .integer = 1 } };
    const result = Push(&args, undefined);
    try std.testing.expect(result == .value and result.value.integer == 0);
}

test "push to empty array" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .boolean = true } };
    const result = Push(&args, undefined);
    try std.testing.expect(result == .value and result.value.integer == 1);
}

test "push multiple elements in sequence" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    var args1 = [_]Types.Value{ .{ .array = array }, .{ .integer = 10 } };
    _ = Push(&args1, undefined);

    var args2 = [_]Types.Value{ .{ .array = array }, .{ .integer = 20 } };
    _ = Push(&args2, undefined);

    var args3 = [_]Types.Value{ .{ .array = array }, .{ .integer = 30 } };
    const result = Push(&args3, undefined);
    try std.testing.expect(result == .value and result.value.integer == 3);
    try std.testing.expectEqual(@as(usize, 3), array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 10), array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 20), array.elements.items[1].integer);
    try std.testing.expectEqual(@as(i64, 30), array.elements.items[2].integer);
}

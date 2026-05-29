const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn Keys(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;
    var iter = Ast.ArrayIterator.initKeys(env.allocator, source) catch {
        return .{ .value = .{ .void = {} } };
    };

    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

const testing = std.testing;

test "keys returns iterator" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Keys(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .iterator);
}

test "keys next returns indices" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });

    var iter = try Ast.ArrayIterator.initKeys(allocator, array);
    defer iter.deinit();

    const v0 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(v0 == .js_object);
    try testing.expect(v0.js_object.properties.get("done").?.boolean == false);
    try testing.expectEqual(@as(i64, 0), v0.js_object.properties.get("value").?.integer);

    const v1 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expectEqual(@as(i64, 1), v1.js_object.properties.get("value").?.integer);

    const v2 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expectEqual(@as(i64, 2), v2.js_object.properties.get("value").?.integer);

    const v3 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(v3.js_object.properties.get("done").?.boolean == true);
}

test "keys empty array returns done" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var iter = try Ast.ArrayIterator.initKeys(allocator, array);
    defer iter.deinit();

    const v = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(v == .js_object);
    try testing.expect(v.js_object.properties.get("done").?.boolean == true);
}

test "keys non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = Keys(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "keys no args returns void" {
    const result = Keys(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

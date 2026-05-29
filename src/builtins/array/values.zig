const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn Values(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;
    var iter = Ast.ArrayIterator.initValues(env.allocator, source) catch {
        return .{ .value = .{ .void = {} } };
    };

    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

const testing = std.testing;

test "values returns iterator" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Values(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .iterator);
}

test "values next returns elements" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });

    var iter = try Ast.ArrayIterator.initValues(allocator, array);
    defer iter.deinit();

    const v0 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(v0 == .js_object);
    try testing.expect(v0.js_object.properties.get("done").?.boolean == false);
    try testing.expectEqualSlices(u8, "a", v0.js_object.properties.get("value").?.string);

    const v1 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expectEqualSlices(u8, "b", v1.js_object.properties.get("value").?.string);

    const v2 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expectEqualSlices(u8, "c", v2.js_object.properties.get("value").?.string);

    const v3 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(v3.js_object.properties.get("done").?.boolean == true);
}

test "values empty array returns done" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var iter = try Ast.ArrayIterator.initValues(allocator, array);
    defer iter.deinit();

    const v = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(v == .js_object);
    try testing.expect(v.js_object.properties.get("done").?.boolean == true);
}

test "values non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = Values(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "values no args returns void" {
    const result = Values(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "values mixed types" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .string = "hello" });
    try array.elements.append(allocator, .{ .boolean = true });

    var iter = try Ast.ArrayIterator.initValues(allocator, array);
    defer iter.deinit();

    const v0 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expectEqual(@as(i64, 1), v0.js_object.properties.get("value").?.integer);

    const v1 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expectEqualSlices(u8, "hello", v1.js_object.properties.get("value").?.string);

    const v2 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expectEqual(true, v2.js_object.properties.get("value").?.boolean);
}

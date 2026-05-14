const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn Entries(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;
    var iter = Ast.ArrayIterator.init(env.allocator, source) catch {
        return .{ .value = .{ .void = {} } };
    };

    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

pub fn IteratorNext(iter: *Ast.ArrayIterator, env: *Types.Environment) Types.Value {
    var result = Ast.ObjectValue.init(env.allocator) catch {
        return .{ .void = {} };
    };
    errdefer result.deinit();

    if (iter.index >= iter.source.elements.items.len) {
        result.properties.put("value", .{ .void = {} }) catch {};
        result.properties.put("done", .{ .boolean = true }) catch {};
        env.objects.append(env.allocator, result) catch {
            result.deinit();
            return .{ .void = {} };
        };
        return .{ .js_object = result };
    }

    var pair = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .void = {} };
    };

    pair.elements.append(env.allocator, .{ .integer = @intCast(iter.index) }) catch {
        pair.deinit();
        return .{ .void = {} };
    };
    pair.elements.append(env.allocator, iter.source.elements.items[iter.index]) catch {
        pair.deinit();
        return .{ .void = {} };
    };

    env.arrays.append(env.allocator, pair) catch {
        pair.deinit();
        return .{ .void = {} };
    };

    result.properties.put("value", .{ .array = pair }) catch {
        return .{ .void = {} };
    };
    result.properties.put("done", .{ .boolean = false }) catch {
        return .{ .void = {} };
    };

    env.objects.append(env.allocator, result) catch {
        result.deinit();
        return .{ .void = {} };
    };

    iter.index += 1;
    return .{ .js_object = result };
}

test "entries returns iterator" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Entries(&args, &env);

    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .iterator);
}

test "iterator next returns pairs" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });

    var iter = try Ast.ArrayIterator.init(allocator, array);
    defer iter.deinit();

    const v0 = IteratorNext(iter, &env);
    try std.testing.expect(v0 == .js_object);
    try std.testing.expect(v0.js_object.properties.get("done").?.boolean == false);
    const pair0 = v0.js_object.properties.get("value").?.array;
    try std.testing.expectEqual(@as(i64, 0), pair0.elements.items[0].integer);
    try std.testing.expectEqualSlices(u8, "a", pair0.elements.items[1].string);

    const v1 = IteratorNext(iter, &env);
    const pair1 = v1.js_object.properties.get("value").?.array;
    try std.testing.expectEqual(@as(i64, 1), pair1.elements.items[0].integer);
    try std.testing.expectEqualSlices(u8, "b", pair1.elements.items[1].string);

    const v2 = IteratorNext(iter, &env);
    const pair2 = v2.js_object.properties.get("value").?.array;
    try std.testing.expectEqual(@as(i64, 2), pair2.elements.items[0].integer);
    try std.testing.expectEqualSlices(u8, "c", pair2.elements.items[1].string);

    const v3 = IteratorNext(iter, &env);
    try std.testing.expect(v3 == .js_object);
    try std.testing.expect(v3.js_object.properties.get("done").?.boolean == true);
    try std.testing.expect(v3.js_object.properties.get("value").? == .void);
}

test "iterator next on empty array returns done" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var iter = try Ast.ArrayIterator.init(allocator, array);
    defer iter.deinit();

    const v = IteratorNext(iter, &env);
    try std.testing.expect(v == .js_object);
    try std.testing.expect(v.js_object.properties.get("done").?.boolean == true);
}

test "entries non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = Entries(&args, undefined);
    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .void);
}

test "entries no args returns void" {
    const result = Entries(&[_]Types.Value{}, undefined);
    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .void);
}

const Environment = @import("../../evaluator.zig").Environment;

const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn flatten(source: *Ast.ArrayObject, depth: u64, allocator: std.mem.Allocator, arrays: *std.ArrayList(*Ast.ArrayObject)) !*Ast.ArrayObject {
    var result = try Ast.ArrayObject.init(allocator);
    errdefer result.deinit();

    try flattenRecursive(source, depth, result, allocator);

    try arrays.append(allocator, result);
    return result;
}

fn flattenRecursive(source: *Ast.ArrayObject, depth: u64, result: *Ast.ArrayObject, allocator: std.mem.Allocator) !void {
    for (source.elements.items) |elem| {
        if (elem == .hole) continue;
        if (elem == .array and depth > 0) {
            try flattenRecursive(elem.array, depth - 1, result, allocator);
        } else {
            try result.elements.append(allocator, elem);
        }
    }
}

pub fn Flat(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) {
        return .{ .value = .{ .void = {} } };
    }

    if (args[0] != .array) {
        return .{ .value = .{ .void = {} } };
    }

    const source = args[0].array;

    const depth: u64 = if (args.len > 1) blk: {
        break :blk switch (args[1]) {
            .integer => |i| if (i < 0) 0 else @as(u64, @intCast(i)),
            .float => |f| if (f < 0) 0 else @as(u64, @intFromFloat(f)),
            else => 1,
        };
    } else 1;

    const result = flatten(source, depth, env.allocator, &env.arrays) catch {
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .array = result } };
}

test "flat flattens one level by default" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    const inner = try Ast.ArrayObject.init(allocator);
    defer inner.deinit();
    try inner.elements.append(allocator, .{ .integer = 3 });
    try inner.elements.append(allocator, .{ .integer = 4 });
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .array = inner });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Flat(&args, &env);

    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 4), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[1].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[2].integer);
    try std.testing.expectEqual(@as(i64, 4), result.value.array.elements.items[3].integer);
}

test "flat with depth 2" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    const inner = try Ast.ArrayObject.init(allocator);
    defer inner.deinit();
    const innerInner = try Ast.ArrayObject.init(allocator);
    defer innerInner.deinit();
    try innerInner.elements.append(allocator, .{ .integer = 5 });
    try innerInner.elements.append(allocator, .{ .integer = 6 });
    try inner.elements.append(allocator, .{ .integer = 3 });
    try inner.elements.append(allocator, .{ .integer = 4 });
    try inner.elements.append(allocator, .{ .array = innerInner });
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .array = inner });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 } };
    const result = Flat(&args, &env);

    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 6), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[1].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[2].integer);
    try std.testing.expectEqual(@as(i64, 4), result.value.array.elements.items[3].integer);
    try std.testing.expectEqual(@as(i64, 5), result.value.array.elements.items[4].integer);
    try std.testing.expectEqual(@as(i64, 6), result.value.array.elements.items[5].integer);
}

test "flat with depth 1 does not flatten nested" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    const inner = try Ast.ArrayObject.init(allocator);
    defer inner.deinit();
    const innerInner = try Ast.ArrayObject.init(allocator);
    defer innerInner.deinit();
    try innerInner.elements.append(allocator, .{ .integer = 5 });
    try inner.elements.append(allocator, .{ .integer = 3 });
    try inner.elements.append(allocator, .{ .array = innerInner });
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .array = inner });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 } };
    const result = Flat(&args, &env);

    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[1].integer);
    try std.testing.expect(result.value.array.elements.items[2] == .array);
    try std.testing.expectEqual(@as(i64, 5), result.value.array.elements.items[2].array.elements.items[0].integer);
}

test "flat with depth 0 returns shallow copy" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    const inner = try Ast.ArrayObject.init(allocator);
    defer inner.deinit();
    try inner.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .array = inner });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 } };
    const result = Flat(&args, &env);

    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 2), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expect(result.value.array.elements.items[1] == .array);
}

test "flat on non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = Flat(&args, undefined);
    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .void);
}

test "flat no args returns void" {
    const result = Flat(&[_]Types.Value{}, undefined);
    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .void);
}

test "flat does not modify original array" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    const inner = try Ast.ArrayObject.init(allocator);
    defer inner.deinit();
    try inner.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .array = inner });

    var args = [_]Types.Value{.{ .array = array }};
    _ = Flat(&args, &env);

    try std.testing.expectEqual(@as(usize, 2), array.elements.items.len);
    try std.testing.expect(array.elements.items[1] == .array);
}

test "flat with negative depth acts as 0" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    const inner = try Ast.ArrayObject.init(allocator);
    defer inner.deinit();
    try inner.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .array = inner });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = -1 } };
    const result = Flat(&args, &env);

    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 2), result.value.array.elements.items.len);
    try std.testing.expect(result.value.array.elements.items[1] == .array);
}

test "flat empty array returns empty array" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = Flat(&args, &env);

    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 0), result.value.array.elements.items.len);
}

test "flat with float depth truncates to integer" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    const inner = try Ast.ArrayObject.init(allocator);
    defer inner.deinit();
    try inner.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .array = inner });

    var args = [_]Types.Value{ .{ .array = array }, .{ .float = 1.9 } };
    const result = Flat(&args, &env);

    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 2), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[1].integer);
}

test "flat with large depth flattens completely" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    const inner = try Ast.ArrayObject.init(allocator);
    defer inner.deinit();
    const innerInner = try Ast.ArrayObject.init(allocator);
    defer innerInner.deinit();
    const innerInnerInner = try Ast.ArrayObject.init(allocator);
    defer innerInnerInner.deinit();
    try innerInnerInner.elements.append(allocator, .{ .integer = 4 });
    try innerInner.elements.append(allocator, .{ .integer = 3 });
    try innerInner.elements.append(allocator, .{ .array = innerInnerInner });
    try inner.elements.append(allocator, .{ .integer = 2 });
    try inner.elements.append(allocator, .{ .array = innerInner });
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .array = inner });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 100 } };
    const result = Flat(&args, &env);

    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 4), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[1].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[2].integer);
    try std.testing.expectEqual(@as(i64, 4), result.value.array.elements.items[3].integer);
}

test "flat handles sparse-like arrays with holes" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    const inner = try Ast.ArrayObject.init(allocator);
    defer inner.deinit();
    try inner.elements.append(allocator, .{ .void = {} });
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .array = inner });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Flat(&args, &env);

    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 2), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expect(result.value.array.elements.items[1] == .void);
}

const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn resolveIndex(raw: i64, len: usize) ?usize {
    if (len == 0) return null;
    var actual = raw;
    if (actual < 0) {
        actual = @as(i64, @intCast(len)) + actual;
    }
    if (actual < 0 or actual >= @as(i64, @intCast(len))) return null;
    return @as(usize, @intCast(actual));
}

pub fn With(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 3) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;
    const len = source.elements.items.len;

    const index_val = args[1];
    const index_raw: i64 = switch (index_val) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => return .{ .value = .{ .void = {} } },
    };

    const resolved = resolveIndex(index_raw, len) orelse {
        return .{ .value = .{ .void = {} } };
    };

    const new_value = args[2];

    var new_array = Ast.ArrayObject.init(source.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    errdefer new_array.deinit();

    new_array.elements.ensureTotalCapacity(source.allocator, len) catch {
        return .{ .value = .{ .void = {} } };
    };

    for (source.elements.items, 0..) |item, i| {
        if (i == resolved) {
            new_array.elements.appendAssumeCapacity(new_value);
        } else {
            new_array.elements.appendAssumeCapacity(item);
        }
    }

    env.arrays.append(env.allocator, new_array) catch {};
    return .{ .value = .{ .array = new_array } };
}

const testing = std.testing;

test "with replaces element at index" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 4 });
    try array.elements.append(allocator, .{ .integer = 5 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 }, .{ .integer = 6 } };
    const result = With(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(i64, 6), result.value.array.elements.items[2].integer);
}

test "with does not mutate original" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 }, .{ .integer = 99 } };
    const result = With(&args, &env);

    try testing.expectEqual(@as(i64, 99), result.value.array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 1), array.elements.items[0].integer);
}

test "with negative index" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 4 });
    try array.elements.append(allocator, .{ .integer = 5 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = -1 }, .{ .integer = 10 } };
    const result = With(&args, &env);

    try testing.expectEqual(@as(i64, 10), result.value.array.elements.items[4].integer);
    try testing.expectEqual(@as(i64, 5), array.elements.items[4].integer);
}

test "with returns new array with same length" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 10 });
    try array.elements.append(allocator, .{ .integer = 20 });
    try array.elements.append(allocator, .{ .integer = 30 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 }, .{ .integer = 100 } };
    const result = With(&args, &env);

    try testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try testing.expectEqual(@as(i64, 100), result.value.array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 20), result.value.array.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 30), result.value.array.elements.items[2].integer);
}

test "with string value replacement" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .string = "z" } };
    const result = With(&args, &env);

    try testing.expectEqualSlices(u8, "z", result.value.array.elements.items[1].string);
}

test "with no args returns void" {
    const result = With(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "with non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 0 }, .{ .integer = 1 } };
    const result = With(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "with out of bounds returns void" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 10 }, .{ .integer = 99 } };
    const result = With(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

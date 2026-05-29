const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn resolveIndex(raw: i64, len: usize) usize {
    if (raw < 0) {
        const abs: i64 = @intCast(@abs(raw));
        if (@as(i64, @intCast(len)) < abs) return 0;
        return @as(usize, @intCast(@as(i64, @intCast(len)) + raw));
    }
    const uraw: usize = @intCast(raw);
    if (uraw > len) return len;
    return uraw;
}

pub fn Slice(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) {
        return .{ .value = .{ .void = {} } };
    }

    if (args[0] != .array) {
        return .{ .value = .{ .void = {} } };
    }

    const source = args[0].array;
    const len = source.elements.items.len;

    const start: i64 = if (args.len > 1) switch (args[1]) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => 0,
    } else 0;

    const end: i64 = if (args.len > 2) switch (args[2]) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => @intCast(len),
    } else @intCast(len);

    const resolved_start = resolveIndex(start, len);
    const resolved_end = resolveIndex(end, len);

    const slice_len = if (resolved_end > resolved_start) resolved_end - resolved_start else 0;

    var new_array = Ast.ArrayObject.init(source.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    errdefer new_array.deinit();

    new_array.elements.ensureTotalCapacity(source.allocator, slice_len) catch {
        return .{ .value = .{ .void = {} } };
    };

    var i: usize = resolved_start;
    while (i < resolved_end) : (i += 1) {
        new_array.elements.appendAssumeCapacity(source.elements.items[i]);
    }

    env.arrays.append(env.allocator, new_array) catch {
        new_array.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .array = new_array } };
}

const testing = std.testing;

fn makeAnimalArray(allocator: std.mem.Allocator) !*Ast.ArrayObject {
    const array = try Ast.ArrayObject.init(allocator);
    try array.elements.append(allocator, .{ .string = "ant" });
    try array.elements.append(allocator, .{ .string = "bison" });
    try array.elements.append(allocator, .{ .string = "camel" });
    try array.elements.append(allocator, .{ .string = "duck" });
    try array.elements.append(allocator, .{ .string = "elephant" });
    return array;
}

test "slice from start index" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try makeAnimalArray(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 } };
    const result = Slice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const sliced = result.value.array;
    try testing.expectEqual(@as(usize, 3), sliced.elements.items.len);
    try testing.expectEqualSlices(u8, "camel", sliced.elements.items[0].string);
    try testing.expectEqualSlices(u8, "duck", sliced.elements.items[1].string);
    try testing.expectEqualSlices(u8, "elephant", sliced.elements.items[2].string);
}

test "slice with start and end" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try makeAnimalArray(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 }, .{ .integer = 4 } };
    const result = Slice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const sliced = result.value.array;
    try testing.expectEqual(@as(usize, 2), sliced.elements.items.len);
    try testing.expectEqualSlices(u8, "camel", sliced.elements.items[0].string);
    try testing.expectEqualSlices(u8, "duck", sliced.elements.items[1].string);
}

test "slice no args returns copy" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try makeAnimalArray(allocator);
    defer array.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = Slice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const sliced = result.value.array;
    try testing.expectEqual(@as(usize, 5), sliced.elements.items.len);
    try testing.expect(sliced != array);
    try testing.expectEqualSlices(u8, "ant", sliced.elements.items[0].string);
    try testing.expectEqualSlices(u8, "elephant", sliced.elements.items[4].string);
}

test "slice negative start" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try makeAnimalArray(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = -2 } };
    const result = Slice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const sliced = result.value.array;
    try testing.expectEqual(@as(usize, 2), sliced.elements.items.len);
    try testing.expectEqualSlices(u8, "duck", sliced.elements.items[0].string);
    try testing.expectEqualSlices(u8, "elephant", sliced.elements.items[1].string);
}

test "slice negative start and end" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try makeAnimalArray(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = -3 }, .{ .integer = -1 } };
    const result = Slice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const sliced = result.value.array;
    try testing.expectEqual(@as(usize, 2), sliced.elements.items.len);
    try testing.expectEqualSlices(u8, "camel", sliced.elements.items[0].string);
    try testing.expectEqualSlices(u8, "duck", sliced.elements.items[1].string);
}

test "slice start > length returns empty" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try makeAnimalArray(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 10 } };
    const result = Slice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 0), result.value.array.elements.items.len);
}

test "slice empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 }, .{ .integer = 2 } };
    const result = Slice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 0), result.value.array.elements.items.len);
}

test "slice numbers" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 10 });
    try array.elements.append(allocator, .{ .integer = 20 });
    try array.elements.append(allocator, .{ .integer = 30 });
    try array.elements.append(allocator, .{ .integer = 40 });
    try array.elements.append(allocator, .{ .integer = 50 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = 3 } };
    const result = Slice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const sliced = result.value.array;
    try testing.expectEqual(@as(usize, 2), sliced.elements.items.len);
    try testing.expectEqual(@as(i64, 20), sliced.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 30), sliced.elements.items[1].integer);
}

test "slice start 0 returns copy of all" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try makeAnimalArray(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 } };
    const result = Slice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 5), result.value.array.elements.items.len);
}

test "slice start equals end returns empty" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try makeAnimalArray(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 }, .{ .integer = 2 } };
    const result = Slice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 0), result.value.array.elements.items.len);
}

test "slice no args returns void" {
    const result = Slice(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "slice non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = Slice(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

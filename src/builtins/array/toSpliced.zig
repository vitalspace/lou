const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn resolveIndex(raw: i64, len: usize) usize {
    if (raw < 0) {
        const abs: u64 = @as(u64, @intCast(-raw));
        if (@as(u64, @intCast(len)) < abs) return 0;
        const res = @as(i64, @intCast(len)) + raw;
        return if (res < 0) 0 else @as(usize, @intCast(res));
    }
    const uraw: usize = @intCast(raw);
    return if (uraw > len) len else uraw;
}

pub fn ToSpliced(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;
    const len = source.elements.items.len;

    const start_raw: i64 = if (args.len > 1) switch (args[1]) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => 0,
    } else 0;

    const start = resolveIndex(start_raw, len);

    const delete_count: usize = if (args.len > 2) blk: {
        const dc = switch (args[2]) {
            .integer => |i| i,
            .float => |f| @as(i64, @intFromFloat(f)),
            else => return .{ .value = .{ .void = {} } },
        };
        if (dc < 0) break :blk 0;
        const udc: usize = @intCast(dc);
        break :blk if (start + udc > len) len - start else udc;
    } else len - start;

    const items_to_insert: []const Types.Value = if (args.len > 3) args[3..] else &.{};

    const new_len = len - delete_count + items_to_insert.len;

    var new_array = Ast.ArrayObject.init(source.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    errdefer new_array.deinit();

    new_array.elements.ensureTotalCapacity(source.allocator, new_len) catch {
        return .{ .value = .{ .void = {} } };
    };

    // copy elements before start
    for (0..start) |i| {
        new_array.elements.appendAssumeCapacity(source.elements.items[i]);
    }

    // insert new items
    for (items_to_insert) |item| {
        new_array.elements.appendAssumeCapacity(item);
    }

    // copy elements after deleted region
    const tail_start = start + delete_count;
    for (tail_start..len) |i| {
        new_array.elements.appendAssumeCapacity(source.elements.items[i]);
    }

    env.arrays.append(env.allocator, new_array) catch {
        new_array.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .array = new_array } };
}

const testing = std.testing;

test "toSpliced returns new array with splice applied" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });
    try array.elements.append(allocator, .{ .string = "d" });
    try array.elements.append(allocator, .{ .string = "e" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = 2 }, .{ .string = "x" }, .{ .string = "y" } };
    const result = ToSpliced(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const spliced = result.value.array;
    try testing.expectEqual(@as(usize, 5), spliced.elements.items.len);
    try testing.expectEqualSlices(u8, "a", spliced.elements.items[0].string);
    try testing.expectEqualSlices(u8, "x", spliced.elements.items[1].string);
    try testing.expectEqualSlices(u8, "y", spliced.elements.items[2].string);
    try testing.expectEqualSlices(u8, "d", spliced.elements.items[3].string);
    try testing.expectEqualSlices(u8, "e", spliced.elements.items[4].string);
}

test "toSpliced does not mutate original" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });
    try array.elements.append(allocator, .{ .string = "d" });
    try array.elements.append(allocator, .{ .string = "e" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = 2 }, .{ .string = "x" }, .{ .string = "y" } };
    _ = ToSpliced(&args, &env);

    try testing.expectEqual(@as(usize, 5), array.elements.items.len);
    try testing.expectEqualSlices(u8, "a", array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "b", array.elements.items[1].string);
    try testing.expectEqualSlices(u8, "c", array.elements.items[2].string);
    try testing.expectEqualSlices(u8, "d", array.elements.items[3].string);
    try testing.expectEqualSlices(u8, "e", array.elements.items[4].string);
}

test "toSpliced returns different array instance" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 }, .{ .integer = 0 }, .{ .string = "x" } };
    const result = ToSpliced(&args, &env);

    try testing.expect(result.value.array != array);
}

test "toSpliced delete only" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });
    try array.elements.append(allocator, .{ .string = "d" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = 2 } };
    const result = ToSpliced(&args, &env);

    const spliced = result.value.array;
    try testing.expectEqual(@as(usize, 2), spliced.elements.items.len);
    try testing.expectEqualSlices(u8, "a", spliced.elements.items[0].string);
    try testing.expectEqualSlices(u8, "d", spliced.elements.items[1].string);

    // original unchanged
    try testing.expectEqual(@as(usize, 4), array.elements.items.len);
}

test "toSpliced insert only" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });
    try array.elements.append(allocator, .{ .string = "d" });
    try array.elements.append(allocator, .{ .string = "e" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 }, .{ .integer = 0 }, .{ .string = "NEW" } };
    const result = ToSpliced(&args, &env);

    const spliced = result.value.array;
    try testing.expectEqual(@as(usize, 6), spliced.elements.items.len);
    try testing.expectEqualSlices(u8, "a", spliced.elements.items[0].string);
    try testing.expectEqualSlices(u8, "b", spliced.elements.items[1].string);
    try testing.expectEqualSlices(u8, "NEW", spliced.elements.items[2].string);
    try testing.expectEqualSlices(u8, "c", spliced.elements.items[3].string);
    try testing.expectEqualSlices(u8, "d", spliced.elements.items[4].string);
    try testing.expectEqualSlices(u8, "e", spliced.elements.items[5].string);
}

test "toSpliced negative start" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });
    try array.elements.append(allocator, .{ .string = "d" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = -2 }, .{ .integer = 1 } };
    const result = ToSpliced(&args, &env);

    const spliced = result.value.array;
    try testing.expectEqual(@as(usize, 3), spliced.elements.items.len);
    try testing.expectEqualSlices(u8, "a", spliced.elements.items[0].string);
    try testing.expectEqualSlices(u8, "b", spliced.elements.items[1].string);
    try testing.expectEqualSlices(u8, "d", spliced.elements.items[2].string);
}

test "toSpliced empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 }, .{ .integer = 0 }, .{ .string = "x" } };
    const result = ToSpliced(&args, &env);

    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
    try testing.expectEqualSlices(u8, "x", result.value.array.elements.items[0].string);
}

test "toSpliced no args returns void" {
    const result = ToSpliced(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "toSpliced non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = ToSpliced(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

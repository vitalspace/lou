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

pub fn Splice(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const arr = args[0].array;
    const len = arr.elements.items.len;

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

    // collect removed elements
    var removed = Ast.ArrayObject.init(arr.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    errdefer removed.deinit();

    for (0..delete_count) |i| {
        removed.elements.append(arr.allocator, arr.elements.items[start + i]) catch {
            return .{ .value = .{ .void = {} } };
        };
    }

    // items to insert (args[3..])
    const items_to_insert: []const Types.Value = if (args.len > 3) args[3..] else &.{};

    const tail_start = start + delete_count;
    const new_len = len - delete_count + items_to_insert.len;

    // ensure capacity for new length
    arr.elements.ensureTotalCapacity(arr.allocator, new_len) catch {
        return .{ .value = .{ .void = {} } };
    };

    if (items_to_insert.len > delete_count) {
        // grow: shift tail right
        const shift = items_to_insert.len - delete_count;
        arr.elements.items.len = new_len;
        var i: usize = len;
        while (i > tail_start) {
            i -= 1;
            arr.elements.items[i + shift] = arr.elements.items[i];
        }
    } else if (items_to_insert.len < delete_count) {
        // shrink: shift tail left
        const shift = delete_count - items_to_insert.len;
        for (tail_start..len) |i| {
            arr.elements.items[i - shift] = arr.elements.items[i];
        }
        arr.elements.items.len = new_len;
    }

    // insert new items at start position
    for (items_to_insert, 0..) |item, i| {
        arr.elements.items[start + i] = item;
    }

    // register removed array so it doesn't leak
    env.arrays.append(env.allocator, removed) catch {};

    return .{ .value = .{ .array = removed } };
}

const testing = std.testing;

test "splice insert at index" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "Jan" });
    try array.elements.append(allocator, .{ .string = "March" });
    try array.elements.append(allocator, .{ .string = "April" });
    try array.elements.append(allocator, .{ .string = "June" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = 0 }, .{ .string = "Feb" } };
    const result = Splice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 0), result.value.array.elements.items.len);
    try testing.expectEqual(@as(usize, 5), array.elements.items.len);
    try testing.expectEqualSlices(u8, "Jan", array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "Feb", array.elements.items[1].string);
    try testing.expectEqualSlices(u8, "March", array.elements.items[2].string);
}

test "splice replace at index" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "Jan" });
    try array.elements.append(allocator, .{ .string = "Feb" });
    try array.elements.append(allocator, .{ .string = "March" });
    try array.elements.append(allocator, .{ .string = "April" });
    try array.elements.append(allocator, .{ .string = "June" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 4 }, .{ .integer = 1 }, .{ .string = "May" } };
    const result = Splice(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
    try testing.expectEqualSlices(u8, "June", result.value.array.elements.items[0].string);
    try testing.expectEqual(@as(usize, 5), array.elements.items.len);
    try testing.expectEqualSlices(u8, "May", array.elements.items[4].string);
}

test "splice delete only" {
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
    const result = Splice(&args, &env);

    try testing.expect(result == .value);
    try testing.expectEqual(@as(usize, 2), result.value.array.elements.items.len);
    try testing.expectEqualSlices(u8, "b", result.value.array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "c", result.value.array.elements.items[1].string);
    try testing.expectEqual(@as(usize, 2), array.elements.items.len);
    try testing.expectEqualSlices(u8, "a", array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "d", array.elements.items[1].string);
}

test "splice no args returns void" {
    const result = Splice(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "splice non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = Splice(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "splice negative start" {
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
    const result = Splice(&args, &env);

    try testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
    try testing.expectEqualSlices(u8, "c", result.value.array.elements.items[0].string);
    try testing.expectEqual(@as(usize, 3), array.elements.items.len);
    try testing.expectEqualSlices(u8, "a", array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "b", array.elements.items[1].string);
    try testing.expectEqualSlices(u8, "d", array.elements.items[2].string);
}

test "splice insert without delete" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "c" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = 0 }, .{ .string = "b" } };
    _ = Splice(&args, &env);

    try testing.expectEqual(@as(usize, 3), array.elements.items.len);
    try testing.expectEqualSlices(u8, "a", array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "b", array.elements.items[1].string);
    try testing.expectEqualSlices(u8, "c", array.elements.items[2].string);
}

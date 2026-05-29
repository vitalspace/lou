const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

fn normalizeIndex(raw: i64, len: i64) i64 {
    if (raw < -len) return 0;
    if (raw < 0) return raw + len;
    return raw;
}

pub fn CopyWithin(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    if (args.len < 2) {
        return .{ .value = .{ .void = {} } };
    }

    if (args[0] != .array) {
        return .{ .value = .{ .void = {} } };
    }

    const array = args[0].array;
    const len = @as(i64, @intCast(array.elements.items.len));

    const target_raw: i64 = switch (args[1]) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => return .{ .value = .{ .void = {} } },
    };
    const target = normalizeIndex(target_raw, len);
    if (target >= len) return .{ .value = .{ .array = array } };

    var start: i64 = 0;
    if (args.len > 2) {
        const start_raw: i64 = switch (args[2]) {
            .integer => |i| i,
            .float => |f| @intFromFloat(f),
            else => return .{ .value = .{ .void = {} } },
        };
        start = normalizeIndex(start_raw, len);
        if (start >= len) return .{ .value = .{ .array = array } };
    }

    var end: i64 = len;
    if (args.len > 3) {
        const end_raw: i64 = switch (args[3]) {
            .integer => |i| i,
            .float => |f| @intFromFloat(f),
            else => return .{ .value = .{ .void = {} } },
        };
        if (end_raw < -len) {
            end = 0;
        } else if (end_raw < 0) {
            end = end_raw + len;
        } else {
            end = end_raw;
        }
        if (end > len) end = len;
    }

    var count = end - start;
    if (count <= 0) return .{ .value = .{ .array = array } };
    if (target + count > len) count = len - target;

    const n = @as(usize, @intCast(count));
    const dst = @as(usize, @intCast(target));
    const src = @as(usize, @intCast(start));

    const items = array.elements.items;
    if (target <= start) {
        std.mem.copyForwards(Types.Value, items[dst..][0..n], items[src..][0..n]);
    } else {
        std.mem.copyBackwards(Types.Value, items[dst..][0..n], items[src..][0..n]);
    }

    return .{ .value = .{ .array = array } };
}

test "copyWithin target start end" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();
    try array.elements.appendSlice(std.testing.allocator, &.{
        .{ .string = "a" }, .{ .string = "b" }, .{ .string = "c" },
        .{ .string = "d" }, .{ .string = "e" },
    });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 }, .{ .integer = 3 }, .{ .integer = 4 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 5), result.value.array.elements.items.len);
    try std.testing.expectEqualSlices(u8, "d", result.value.array.elements.items[0].string);
    try std.testing.expectEqualSlices(u8, "b", result.value.array.elements.items[1].string);
    try std.testing.expectEqualSlices(u8, "c", result.value.array.elements.items[2].string);
    try std.testing.expectEqualSlices(u8, "d", result.value.array.elements.items[3].string);
    try std.testing.expectEqualSlices(u8, "e", result.value.array.elements.items[4].string);
}

test "copyWithin start to end" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();
    try array.elements.appendSlice(std.testing.allocator, &.{
        .{ .string = "a" }, .{ .string = "b" }, .{ .string = "c" },
        .{ .string = "d" }, .{ .string = "e" },
    });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = 3 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expectEqual(@as(usize, 5), result.value.array.elements.items.len);
    try std.testing.expectEqualSlices(u8, "a", result.value.array.elements.items[0].string);
    try std.testing.expectEqualSlices(u8, "d", result.value.array.elements.items[1].string);
    try std.testing.expectEqualSlices(u8, "e", result.value.array.elements.items[2].string);
    try std.testing.expectEqualSlices(u8, "d", result.value.array.elements.items[3].string);
    try std.testing.expectEqualSlices(u8, "e", result.value.array.elements.items[4].string);
}

test "copyWithin negative indices" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();
    try array.elements.appendSlice(std.testing.allocator, &.{
        .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 },
        .{ .integer = 4 }, .{ .integer = 5 },
    });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = -2 }, .{ .integer = -3 }, .{ .integer = -1 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[1].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[2].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[3].integer);
    try std.testing.expectEqual(@as(i64, 4), result.value.array.elements.items[4].integer);
}

test "copyWithin target beyond length" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();
    try array.elements.appendSlice(std.testing.allocator, &.{
        .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 },
    });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 10 }, .{ .integer = 0 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
}

test "copyWithin start beyond length" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();
    try array.elements.appendSlice(std.testing.allocator, &.{
        .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 },
    });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 }, .{ .integer = 10 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
}

test "copyWithin overlap backward copy" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();
    try array.elements.appendSlice(std.testing.allocator, &.{
        .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 },
        .{ .integer = 4 }, .{ .integer = 5 },
    });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 }, .{ .integer = 0 }, .{ .integer = 4 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expectEqual(@as(usize, 5), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[1].integer);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[2].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[3].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[4].integer);
}

test "copyWithin no start copies from 0" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();
    try array.elements.appendSlice(std.testing.allocator, &.{
        .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 },
        .{ .integer = 4 }, .{ .integer = 5 },
    });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[1].integer);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[2].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[3].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[4].integer);
}

test "copyWithin empty array" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 }, .{ .integer = 0 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expectEqual(@as(usize, 0), result.value.array.elements.items.len);
}

test "copyWithin no args returns void" {
    const result = CopyWithin(&[_]Types.Value{}, undefined);
    try std.testing.expect(result.value == .void);
}

test "copyWithin non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 0 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expect(result.value == .void);
}

test "copyWithin negative target before -len" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();
    try array.elements.appendSlice(std.testing.allocator, &.{
        .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 },
    });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = -10 }, .{ .integer = 1 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[1].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[2].integer);
}

test "copyWithin end implies position before start" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();
    try array.elements.appendSlice(std.testing.allocator, &.{
        .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 },
    });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 }, .{ .integer = 2 }, .{ .integer = 1 } };
    const result = CopyWithin(&args, undefined);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[1].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[2].integer);
}

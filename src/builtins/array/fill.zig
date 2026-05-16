const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const testing = std.testing;

fn toInt(v: Types.Value, fallback: i64) i64 {
    return switch (v) {
        .integer => |i| i,
        .float => |f| {
            if (std.math.isNan(f)) return fallback;
            return @intFromFloat(f);
        },
        else => fallback,
    };
}

pub fn Fill(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const array = args[0].array;
    const value = args[1];
    const len = @as(i64, @intCast(array.elements.items.len));

    var start: i64 = 0;
    if (args.len >= 3) start = toInt(args[2], 0);
    if (start < -len) { start = 0; } else if (start < 0) { start += len; }

    var end: i64 = len;
    if (args.len >= 4) end = toInt(args[3], len);
    if (end < -len) { end = 0; } else if (end < 0) { end += len; }
    if (end > len) end = len;

    if (start >= len or start >= end) return .{ .value = .{ .array = array } };

    const s = @as(usize, @intCast(start));
    const e = @as(usize, @intCast(end));
    for (array.elements.items[s..e]) |*item| item.* = value;

    return .{ .value = .{ .array = array } };
}

test "fill fills array with value" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 } };
    const result = Fill(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items[0].integer == 99);
    try testing.expect(result.value.array.elements.items[1].integer == 99);
    try testing.expect(result.value.array.elements.items[2].integer == 99);
}

test "fill with start index" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 4 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .integer = 2 } };
    const result = Fill(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items[0].integer == 1);
    try testing.expect(result.value.array.elements.items[1].integer == 2);
    try testing.expect(result.value.array.elements.items[2].integer == 99);
    try testing.expect(result.value.array.elements.items[3].integer == 99);
}

test "fill with start and end index" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 4 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .integer = 1 }, .{ .integer = 3 } };
    const result = Fill(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items[0].integer == 1);
    try testing.expect(result.value.array.elements.items[1].integer == 99);
    try testing.expect(result.value.array.elements.items[2].integer == 99);
    try testing.expect(result.value.array.elements.items[3].integer == 4);
}

test "fill with negative start index" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 4 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .integer = -2 } };
    const result = Fill(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items[0].integer == 1);
    try testing.expect(result.value.array.elements.items[1].integer == 2);
    try testing.expect(result.value.array.elements.items[2].integer == 99);
    try testing.expect(result.value.array.elements.items[3].integer == 99);
}

test "fill with negative end index" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 4 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .integer = 0 }, .{ .integer = -1 } };
    const result = Fill(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items[0].integer == 99);
    try testing.expect(result.value.array.elements.items[1].integer == 99);
    try testing.expect(result.value.array.elements.items[2].integer == 99);
    try testing.expect(result.value.array.elements.items[3].integer == 4);
}

test "fill empty array returns array" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 } };
    const result = Fill(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items.len == 0);
}

test "fill no args returns void" {
    const result = Fill(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "fill non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 99 } };
    const result = Fill(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "fill with start >= len returns array unchanged" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .integer = 5 } };
    const result = Fill(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items[0].integer == 1);
    try testing.expect(result.value.array.elements.items[1].integer == 2);
}

test "fill with start >= end returns array unchanged" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .integer = 1 }, .{ .integer = 1 } };
    const result = Fill(&args, undefined);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items[0].integer == 1);
    try testing.expect(result.value.array.elements.items[1].integer == 2);
}

test "fill with float start index truncates" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .float = 1.7 } };
    const result = Fill(&args, undefined);

    try testing.expect(result.value.array.elements.items[0].integer == 1);
    try testing.expect(result.value.array.elements.items[1].integer == 99);
    try testing.expect(result.value.array.elements.items[2].integer == 99);
}

test "fill with NaN start treated as 0" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .float = std.math.nan(f64) } };
    const result = Fill(&args, undefined);

    try testing.expect(result.value.array.elements.items[0].integer == 99);
    try testing.expect(result.value.array.elements.items[1].integer == 99);
    try testing.expect(result.value.array.elements.items[2].integer == 99);
}

test "fill with NaN end treated as len" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .integer = 0 }, .{ .float = std.math.nan(f64) } };
    const result = Fill(&args, undefined);

    try testing.expect(result.value.array.elements.items[0].integer == 99);
    try testing.expect(result.value.array.elements.items[1].integer == 99);
    try testing.expect(result.value.array.elements.items[2].integer == 99);
}

test "fill negative start beyond -len clamps to 0" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .integer = -10 } };
    const result = Fill(&args, undefined);

    try testing.expect(result.value.array.elements.items[0].integer == 99);
    try testing.expect(result.value.array.elements.items[1].integer == 99);
    try testing.expect(result.value.array.elements.items[2].integer == 99);
}

test "fill negative end beyond -len clamps to 0" {
    const allocator = testing.allocator;
    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 99 }, .{ .integer = 0 }, .{ .integer = -10 } };
    const result = Fill(&args, undefined);

    try testing.expect(result.value.array.elements.items[0].integer == 1);
    try testing.expect(result.value.array.elements.items[1].integer == 2);
    try testing.expect(result.value.array.elements.items[2].integer == 3);
}

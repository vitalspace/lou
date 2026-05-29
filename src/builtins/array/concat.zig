const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn Concat(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) {
        return .{ .value = .{ .void = {} } };
    }

    if (args[0] != .array) {
        return .{ .value = .{ .void = {} } };
    }

    const source = args[0].array;

    var total_len: usize = source.elements.items.len;
    for (args[1..]) |arg| {
        total_len += if (arg == .array) arg.array.elements.items.len else 1;
    }

    var new_array = Ast.ArrayObject.init(source.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    errdefer new_array.deinit();

    new_array.elements.ensureTotalCapacity(source.allocator, total_len) catch {
        return .{ .value = .{ .void = {} } };
    };

    new_array.elements.appendSliceAssumeCapacity(source.elements.items);

    for (args[1..]) |arg| {
        if (arg == .array) {
            new_array.elements.appendSliceAssumeCapacity(arg.array.elements.items);
        } else {
            new_array.elements.appendAssumeCapacity(arg);
        }
    }

    env.arrays.append(env.allocator, new_array) catch {
        new_array.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .array = new_array } };
}

test "concat two arrays" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array1 = try Ast.ArrayObject.init(allocator);
    defer array1.deinit();
    try array1.elements.append(allocator, .{ .string = "a" });
    try array1.elements.append(allocator, .{ .string = "b" });
    try array1.elements.append(allocator, .{ .string = "c" });

    const array2 = try Ast.ArrayObject.init(allocator);
    defer array2.deinit();
    try array2.elements.append(allocator, .{ .string = "d" });
    try array2.elements.append(allocator, .{ .string = "e" });
    try array2.elements.append(allocator, .{ .string = "f" });

    var args = [_]Types.Value{ .{ .array = array1 }, .{ .array = array2 } };
    const result = Concat(&args, &env);
    // Result array is tracked by env, no need for manual deinit

    try std.testing.expect(result == .value);
    try std.testing.expectEqual(@as(usize, 6), result.value.array.elements.items.len);
    try std.testing.expectEqualSlices(u8, "a", result.value.array.elements.items[0].string);
    try std.testing.expectEqualSlices(u8, "b", result.value.array.elements.items[1].string);
    try std.testing.expectEqualSlices(u8, "c", result.value.array.elements.items[2].string);
    try std.testing.expectEqualSlices(u8, "d", result.value.array.elements.items[3].string);
    try std.testing.expectEqualSlices(u8, "e", result.value.array.elements.items[4].string);
    try std.testing.expectEqualSlices(u8, "f", result.value.array.elements.items[5].string);
}

test "concat three arrays" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const num1 = try Ast.ArrayObject.init(allocator);
    defer num1.deinit();
    try num1.elements.append(allocator, .{ .integer = 1 });
    try num1.elements.append(allocator, .{ .integer = 2 });
    try num1.elements.append(allocator, .{ .integer = 3 });

    const num2 = try Ast.ArrayObject.init(allocator);
    defer num2.deinit();
    try num2.elements.append(allocator, .{ .integer = 4 });
    try num2.elements.append(allocator, .{ .integer = 5 });
    try num2.elements.append(allocator, .{ .integer = 6 });

    const num3 = try Ast.ArrayObject.init(allocator);
    defer num3.deinit();
    try num3.elements.append(allocator, .{ .integer = 7 });
    try num3.elements.append(allocator, .{ .integer = 8 });
    try num3.elements.append(allocator, .{ .integer = 9 });

    var args = [_]Types.Value{ .{ .array = num1 }, .{ .array = num2 }, .{ .array = num3 } };
    const result = Concat(&args, &env);

    try std.testing.expectEqual(@as(usize, 9), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 9), result.value.array.elements.items[8].integer);
}

test "concat values to array" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const letters = try Ast.ArrayObject.init(allocator);
    defer letters.deinit();
    try letters.elements.append(allocator, .{ .string = "a" });
    try letters.elements.append(allocator, .{ .string = "b" });
    try letters.elements.append(allocator, .{ .string = "c" });

    const array2 = try Ast.ArrayObject.init(allocator);
    defer array2.deinit();
    try array2.elements.append(allocator, .{ .integer = 2 });
    try array2.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = letters }, .{ .integer = 1 }, .{ .array = array2 } };
    const result = Concat(&args, &env);

    try std.testing.expectEqual(@as(usize, 6), result.value.array.elements.items.len);
    try std.testing.expectEqualSlices(u8, "a", result.value.array.elements.items[0].string);
    try std.testing.expectEqualSlices(u8, "c", result.value.array.elements.items[2].string);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[3].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[4].integer);
    try std.testing.expectEqual(@as(i64, 3), result.value.array.elements.items[5].integer);
}

test "concat nested arrays" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const num1 = try Ast.ArrayObject.init(allocator);
    defer num1.deinit();
    const inner = try Ast.ArrayObject.init(allocator);
    defer inner.deinit();
    try inner.elements.append(allocator, .{ .integer = 1 });
    try num1.elements.append(allocator, .{ .array = inner });

    const num2 = try Ast.ArrayObject.init(allocator);
    defer num2.deinit();
    try num2.elements.append(allocator, .{ .integer = 2 });
    const inner2 = try Ast.ArrayObject.init(allocator);
    defer inner2.deinit();
    try inner2.elements.append(allocator, .{ .integer = 3 });
    try num2.elements.append(allocator, .{ .array = inner2 });

    var args = [_]Types.Value{ .{ .array = num1 }, .{ .array = num2 } };
    const result = Concat(&args, &env);

    try std.testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try std.testing.expect(result.value.array.elements.items[0] == .array);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[1].integer);
    try std.testing.expect(result.value.array.elements.items[2] == .array);
}

test "concat does not modify original arrays" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array1 = try Ast.ArrayObject.init(allocator);
    defer array1.deinit();
    try array1.elements.append(allocator, .{ .integer = 1 });

    const array2 = try Ast.ArrayObject.init(allocator);
    defer array2.deinit();
    try array2.elements.append(allocator, .{ .integer = 2 });

    var args = [_]Types.Value{ .{ .array = array1 }, .{ .array = array2 } };
    const result = Concat(&args, &env);

    try std.testing.expectEqual(@as(usize, 1), array1.elements.items.len);
    try std.testing.expectEqual(@as(usize, 1), array2.elements.items.len);
    try std.testing.expectEqual(@as(usize, 2), result.value.array.elements.items.len);
}

test "concat no args returns copy" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Concat(&args, &env);

    try std.testing.expectEqual(@as(usize, 2), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.value.array.elements.items[1].integer);
}

test "concat empty array" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array1 = try Ast.ArrayObject.init(allocator);
    defer array1.deinit();

    const array2 = try Ast.ArrayObject.init(allocator);
    defer array2.deinit();
    try array2.elements.append(allocator, .{ .integer = 1 });

    var args = [_]Types.Value{ .{ .array = array1 }, .{ .array = array2 } };
    const result = Concat(&args, &env);

    try std.testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
}

test "concat with mixed types" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });

    var args = [_]Types.Value{
        .{ .array = array },
        .{ .boolean = true },
        .{ .null = {} },
        .{ .string = "hello" },
        .{ .float = 3.14 },
    };
    const result = Concat(&args, &env);

    try std.testing.expectEqual(@as(usize, 5), result.value.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try std.testing.expectEqual(true, result.value.array.elements.items[1].boolean);
    try std.testing.expect(result.value.array.elements.items[2] == .null);
    try std.testing.expectEqualSlices(u8, "hello", result.value.array.elements.items[3].string);
    try std.testing.expectEqual(@as(f64, 3.14), result.value.array.elements.items[4].float);
}

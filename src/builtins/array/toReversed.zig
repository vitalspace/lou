const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn ToReversed(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;
    const len = source.elements.items.len;

    var new_array = Ast.ArrayObject.init(source.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    errdefer new_array.deinit();

    if (len == 0) {
        env.arrays.append(env.allocator, new_array) catch {
            new_array.deinit();
            return .{ .value = .{ .void = {} } };
        };
        return .{ .value = .{ .array = new_array } };
    }

    new_array.elements.ensureTotalCapacity(source.allocator, len) catch {
        return .{ .value = .{ .void = {} } };
    };

    var i: usize = len;
    while (i > 0) {
        i -= 1;
        new_array.elements.appendAssumeCapacity(source.elements.items[i]);
    }

    env.arrays.append(env.allocator, new_array) catch {
        new_array.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .array = new_array } };
}

const testing = std.testing;

test "toReversed returns new reversed array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToReversed(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const reversed = result.value.array;
    try testing.expectEqual(@as(usize, 3), reversed.elements.items.len);
    try testing.expectEqual(@as(i64, 3), reversed.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 2), reversed.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 1), reversed.elements.items[2].integer);
}

test "toReversed does not mutate original" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{.{ .array = array }};
    _ = ToReversed(&args, &env);

    try testing.expectEqual(@as(i64, 1), array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 2), array.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 3), array.elements.items[2].integer);
}

test "toReversed returns different array instance" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToReversed(&args, &env);

    try testing.expect(result.value.array != array);
}

test "toReversed strings" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "c" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToReversed(&args, &env);

    try testing.expectEqualSlices(u8, "c", result.value.array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "b", result.value.array.elements.items[1].string);
    try testing.expectEqualSlices(u8, "a", result.value.array.elements.items[2].string);
}

test "toReversed empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToReversed(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 0), result.value.array.elements.items.len);
}

test "toReversed single element" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 42 });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToReversed(&args, &env);

    try testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
    try testing.expectEqual(@as(i64, 42), result.value.array.elements.items[0].integer);
}

test "toReversed no args returns void" {
    const result = ToReversed(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "toReversed non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = ToReversed(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

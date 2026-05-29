const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn valEq(l: Types.Value, r: Types.Value) bool {
    return switch (l) {
        .integer => |li| switch (r) {
            .integer => |ri| li == ri,
            .float => |rf| @as(f64, @floatFromInt(li)) == rf,
            else => false,
        },
        .float => |lf| switch (r) {
            .float => |rf| lf == rf,
            .integer => |ri| lf == @as(f64, @floatFromInt(ri)),
            else => false,
        },
        .string => |ls| switch (r) {
            .string => |rs| std.mem.eql(u8, ls, rs),
            else => false,
        },
        .boolean => |lb| switch (r) {
            .boolean => |rb| lb == rb,
            else => false,
        },
        .void => r == .void,
        .null => r == .null,
        else => false,
    };
}

pub fn LastIndexOf(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2) return .{ .value = .{ .integer = -1 } };
    if (args[0] != .array) return .{ .value = .{ .integer = -1 } };

    const source = args[0].array;
    const search_element = args[1];

    const len = source.elements.items.len;
    if (len == 0) return .{ .value = .{ .integer = -1 } };

    var from_index: i64 = @intCast(len - 1);
    if (args.len > 2) {
        from_index = switch (args[2]) {
            .integer => |i| i,
            .float => |f| @as(i64, @intFromFloat(f)),
            else => from_index,
        };
    }

    if (from_index < 0) {
        from_index = @max(0, @as(i64, @intCast(len)) + from_index);
    }

    if (from_index >= @as(i64, @intCast(len))) {
        from_index = @intCast(len - 1);
    }

    var i: i64 = from_index;
    while (i >= 0) {
        if (valEq(source.elements.items[@as(usize, @intCast(i))], search_element)) {
            return .{ .value = .{ .integer = i } };
        }
        i -= 1;
    }

    return .{ .value = .{ .integer = -1 } };
}

const testing = std.testing;

test "lastIndexOf finds last occurrence" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "Dodo" });
    try array.elements.append(allocator, .{ .string = "Tiger" });
    try array.elements.append(allocator, .{ .string = "Penguin" });
    try array.elements.append(allocator, .{ .string = "Dodo" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "Dodo" } };
    const result = LastIndexOf(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 3), result.value.integer);
}

test "lastIndexOf with fromIndex" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "Dodo" });
    try array.elements.append(allocator, .{ .string = "Tiger" });
    try array.elements.append(allocator, .{ .string = "Penguin" });
    try array.elements.append(allocator, .{ .string = "Dodo" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "Dodo" }, .{ .integer = 2 } };
    const result = LastIndexOf(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "lastIndexOf returns -1 when not found" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "Dodo" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "giraffe" } };
    const result = LastIndexOf(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "lastIndexOf empty array returns -1" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 } };
    const result = LastIndexOf(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "lastIndexOf no args returns -1" {
    const result = LastIndexOf(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "lastIndexOf non-array returns -1" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 42 } };
    const result = LastIndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "lastIndexOf with negative fromIndex" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 1 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = -2 } };
    const result = LastIndexOf(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

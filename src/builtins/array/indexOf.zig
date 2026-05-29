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
        .hole => r == .void,
        else => false,
    };
}

pub fn IndexOf(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2) return .{ .value = .{ .integer = -1 } };
    if (args[0] != .array) return .{ .value = .{ .integer = -1 } };

    const source = args[0].array;
    const search_element = args[1];

    var from_index: i64 = 0;
    if (args.len > 2) {
        from_index = switch (args[2]) {
            .integer => |i| i,
            .float => |f| @as(i64, @intFromFloat(f)),
            else => 0,
        };
    }

    if (from_index < 0) {
        from_index = @max(0, @as(i64, @intCast(source.elements.items.len)) + from_index);
    }

    if (from_index >= @as(i64, @intCast(source.elements.items.len))) {
        return .{ .value = .{ .integer = -1 } };
    }

    var i: usize = @as(usize, @intCast(from_index));
    while (i < source.elements.items.len) : (i += 1) {
        if (source.elements.items[i] == .hole) continue;
        if (valEq(source.elements.items[i], search_element)) {
            return .{ .value = .{ .integer = @intCast(i) } };
        }
    }

    return .{ .value = .{ .integer = -1 } };
}

const testing = std.testing;

test "indexOf finds element" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "ant" });
    try array.elements.append(allocator, .{ .string = "bison" });
    try array.elements.append(allocator, .{ .string = "camel" });
    try array.elements.append(allocator, .{ .string = "duck" });
    try array.elements.append(allocator, .{ .string = "bison" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "bison" } };
    const result = IndexOf(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 1), result.value.integer);
}

test "indexOf with fromIndex" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "ant" });
    try array.elements.append(allocator, .{ .string = "bison" });
    try array.elements.append(allocator, .{ .string = "camel" });
    try array.elements.append(allocator, .{ .string = "duck" });
    try array.elements.append(allocator, .{ .string = "bison" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "bison" }, .{ .integer = 2 } };
    const result = IndexOf(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 4), result.value.integer);
}

test "indexOf returns -1 when not found" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "ant" });
    try array.elements.append(allocator, .{ .string = "bison" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "giraffe" } };
    const result = IndexOf(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "indexOf empty array returns -1" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 } };
    const result = IndexOf(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "indexOf no args returns -1" {
    const result = IndexOf(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "indexOf non-array returns -1" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 42 } };
    const result = IndexOf(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "indexOf with negative fromIndex" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = -2 } };
    const result = IndexOf(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

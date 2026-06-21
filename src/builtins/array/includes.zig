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
        .big_int => |lb| switch (r) {
            .big_int => |rb| lb.compare(rb) == .eq,
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

pub fn Includes(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2) return .{ .value = .{ .boolean = false } };
    if (args[0] != .array) return .{ .value = .{ .boolean = false } };

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

    var i: usize = @as(usize, @intCast(from_index));
    while (i < source.elements.items.len) : (i += 1) {
        if (valEq(source.elements.items[i], search_element)) {
            return .{ .value = .{ .boolean = true } };
        }
    }

    return .{ .value = .{ .boolean = false } };
}

const testing = std.testing;

test "includes finds element" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 } };
    const result = Includes(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(result.value.boolean);
}

test "includes returns false when not found" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 4 } };
    const result = Includes(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(!result.value.boolean);
}

test "includes with fromIndex" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 }, .{ .integer = 2 } };
    const result = Includes(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(result.value.boolean);
}

test "includes with fromIndex past element returns false" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 }, .{ .integer = 2 } };
    const result = Includes(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(!result.value.boolean);
}

test "includes empty array returns false" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 1 } };
    const result = Includes(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(!result.value.boolean);
}

test "includes string elements" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "cat" });
    try array.elements.append(allocator, .{ .string = "dog" });
    try array.elements.append(allocator, .{ .string = "bat" });

    var found = [_]Types.Value{ .{ .array = array }, .{ .string = "cat" } };
    const result1 = Includes(&found, &env);
    try testing.expect(result1.value.boolean);

    var not_found = [_]Types.Value{ .{ .array = array }, .{ .string = "at" } };
    const result2 = Includes(&not_found, &env);
    try testing.expect(!result2.value.boolean);
}

test "includes non-array returns false" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 42 } };
    const result = Includes(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(!result.value.boolean);
}

test "includes no args returns false" {
    const result = Includes(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(!result.value.boolean);
}

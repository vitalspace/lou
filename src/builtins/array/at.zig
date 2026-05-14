const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn At(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    if (args.len != 2) {
        return .{ .value = .{ .void = {} } };
    }

    const array_val = args[0];
    if (array_val != .array) {
        return .{ .value = .{ .void = {} } };
    }

    const index_val = args[1];
    const index: i64 = switch (index_val) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => return .{ .value = .{ .void = {} } },
    };

    const len = @as(i64, @intCast(array_val.array.elements.items.len));
    var actual_index = index;
    if (actual_index < 0) {
        actual_index = len + actual_index;
    }

    if (actual_index < 0 or actual_index >= len) {
        return .{ .value = .{ .void = {} } };
    }

    return .{ .value = array_val.array.elements.items[@as(usize, @intCast(actual_index))] };
}

test "at positive index" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 5 });
    try array.elements.append(array.allocator, .{ .integer = 12 });
    try array.elements.append(array.allocator, .{ .integer = 8 });
    try array.elements.append(array.allocator, .{ .integer = 130 });
    try array.elements.append(array.allocator, .{ .integer = 44 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 2 } };
    const result = At(&args, undefined);
    try std.testing.expectEqual(@as(i64, 8), result.value.integer);
}

test "at negative index" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 5 });
    try array.elements.append(array.allocator, .{ .integer = 12 });
    try array.elements.append(array.allocator, .{ .integer = 8 });
    try array.elements.append(array.allocator, .{ .integer = 130 });
    try array.elements.append(array.allocator, .{ .integer = 44 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = -2 } };
    const result = At(&args, undefined);
    try std.testing.expectEqual(@as(i64, 130), result.value.integer);
}

test "at out of bounds positive returns undefined" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 10 } };
    const result = At(&args, undefined);
    try std.testing.expect(result == .value and result.value == .void);
}

test "at out of bounds negative returns undefined" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = -10 } };
    const result = At(&args, undefined);
    try std.testing.expect(result == .value and result.value == .void);
}

test "at first element" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .string = "first" });
    try array.elements.append(array.allocator, .{ .string = "second" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 } };
    const result = At(&args, undefined);
    try std.testing.expectEqualSlices(u8, "first", result.value.string);
}

test "at last element with -1" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .float = 1.5 });
    try array.elements.append(array.allocator, .{ .float = 2.5 });
    try array.elements.append(array.allocator, .{ .float = 3.5 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = -1 } };
    const result = At(&args, undefined);
    try std.testing.expectEqual(@as(f64, 3.5), result.value.float);
}

test "at empty array returns undefined" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .integer = 0 } };
    const result = At(&args, undefined);
    try std.testing.expect(result == .value and result.value == .void);
}

test "at no args returns undefined" {
    const result = At(&[_]Types.Value{}, undefined);
    try std.testing.expect(result == .value and result.value == .void);
}

test "at non-array returns undefined" {
    var args = [_]Types.Value{ .{ .float = 42.0 }, .{ .integer = 0 } };
    const result = At(&args, undefined);
    try std.testing.expect(result == .value and result.value == .void);
}

test "at float index truncates" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 10 });
    try array.elements.append(array.allocator, .{ .integer = 20 });
    try array.elements.append(array.allocator, .{ .integer = 30 });

    var args = [_]Types.Value{ .{ .array = array }, .{ .float = 1.9 } };
    const result = At(&args, undefined);
    try std.testing.expectEqual(@as(i64, 20), result.value.integer);
}

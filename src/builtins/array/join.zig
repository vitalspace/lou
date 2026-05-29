const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn valToString(val: Types.Value, allocator: std.mem.Allocator) ![]const u8 {
    return switch (val) {
        .integer => |i| std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| std.fmt.allocPrint(allocator, "{d}", .{f}),
        .string => |s| try allocator.dupe(u8, s),
        .boolean => |b| try allocator.dupe(u8, if (b) "true" else "false"),
        .null, .void => try allocator.dupe(u8, ""),
        else => try allocator.dupe(u8, ""),
    };
}

pub fn Join(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;
    const separator = if (args.len > 1) switch (args[1]) {
        .string => |s| s,
        else => ",",
    } else ",";

    if (source.elements.items.len == 0) return .{ .value = .{ .string = "" } };

    var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch return .{ .value = .{ .void = {} } };
    defer buf.deinit(env.allocator);

    for (source.elements.items, 0..) |element, i| {
        if (i > 0) {
            buf.appendSlice(env.allocator, separator) catch return .{ .value = .{ .void = {} } };
        }
        const str = valToString(element, env.allocator) catch return .{ .value = .{ .void = {} } };
        buf.appendSlice(env.allocator, str) catch {
            env.allocator.free(str);
            return .{ .value = .{ .void = {} } };
        };
        env.allocator.free(str);
    }

    const owned = buf.toOwnedSlice(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.owned_strings.append(env.allocator, owned) catch {};
    return .{ .value = .{ .string = owned } };
}

const testing = std.testing;

test "join with default separator" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "Fire" });
    try array.elements.append(allocator, .{ .string = "Air" });
    try array.elements.append(allocator, .{ .string = "Water" });

    var args = [_]Types.Value{ .{ .array = array } };
    const result = Join(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "Fire,Air,Water", result.value.string);
}

test "join with custom separator" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "Fire" });
    try array.elements.append(allocator, .{ .string = "Air" });
    try array.elements.append(allocator, .{ .string = "Water" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = ", " } };
    const result = Join(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "Fire, Air, Water", result.value.string);
}

test "join with empty separator" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "Fire" });
    try array.elements.append(allocator, .{ .string = "Air" });

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "" } };
    const result = Join(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "FireAir", result.value.string);
}

test "join empty array returns empty string" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array } };
    const result = Join(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "", result.value.string);
}

test "join single element" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "hello" });

    var args = [_]Types.Value{ .{ .array = array } };
    const result = Join(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "hello", result.value.string);
}

test "join non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 } };
    const result = Join(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "join no args returns void" {
    const result = Join(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "join mixed types" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .string = "hello" });
    try array.elements.append(allocator, .{ .boolean = true });

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "-" } };
    const result = Join(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "1-hello-true", result.value.string);
}

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

pub fn ToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;

    if (source.elements.items.len == 0) return .{ .value = .{ .string = "" } };

    var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch return .{ .value = .{ .void = {} } };
    defer buf.deinit(env.allocator);

    for (source.elements.items, 0..) |element, i| {
        if (i > 0) {
            buf.appendSlice(env.allocator, ",") catch return .{ .value = .{ .void = {} } };
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

test "toString basic" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .string = "a" });
    try array.elements.append(allocator, .{ .string = "1a" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToString(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "1,2,a,1a", result.value.string);
}

test "toString empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToString(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "", result.value.string);
}

test "toString integers" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToString(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "1,2,3", result.value.string);
}

test "toString boolean types" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .boolean = true });
    try array.elements.append(allocator, .{ .boolean = false });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToString(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, "true,false", result.value.string);
}

test "toString null and undefined" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .null = {} });
    try array.elements.append(allocator, .{ .void = {} });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToString(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualSlices(u8, ",", result.value.string);
}

test "toString no args returns void" {
    const result = ToString(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "toString non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = ToString(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

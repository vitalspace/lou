const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn Repeat(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    const count: i64 = if (args.len >= 2) switch (args[1]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => 0,
        .null => 0,
        .boolean => if (args[1].boolean) 1 else 0,
        else => 0,
    } else 0;

    if (count < 0) return .{ .value = .{ .string = "" } };
    if (count == 0) {
        const result = env.allocator.dupe(u8, "") catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const total_len = s.len * @as(usize, @intCast(count));
    var buf = std.ArrayList(u8).initCapacity(env.allocator, total_len) catch {
        return .{ .value = .{ .string = "" } };
    };

    var i: usize = 0;
    while (i < @as(usize, @intCast(count))) : (i += 1) {
        buf.appendSlice(env.allocator, s) catch {};
    }

    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "repeat twice" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Because I'm happy. " }, .{ .integer = 2 } };
    const result = Repeat(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("Because I'm happy. Because I'm happy. ", result.value.string);
}

test "repeat zero times returns empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 0 } };
    const result = Repeat(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "repeat once returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 1 } };
    const result = Repeat(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "repeat empty string returns empty" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" }, .{ .integer = 5 } };
    const result = Repeat(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "repeat negative count returns empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = -1 } };
    const result = Repeat(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "repeat single character" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "x" }, .{ .integer = 5 } };
    const result = Repeat(&args, &env);
    try testing.expectEqualStrings("xxxxx", result.value.string);
}

test "repeat no args returns empty" {
    const result = Repeat(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "repeat non-string returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 2 } };
    const result = Repeat(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

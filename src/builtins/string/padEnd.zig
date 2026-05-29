const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn PadEnd(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    const target_length: i64 = if (args.len >= 2) switch (args[1]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => 0,
        .null => 0,
        .boolean => if (args[1].boolean) 1 else 0,
        else => 0,
    } else 0;

    if (target_length <= s.len) {
        const result = env.allocator.dupe(u8, s) catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const pad_string = if (args.len >= 3) switch (args[2]) {
        .string => |ps| ps,
        .void => " ",
        .null => " ",
        else => " ",
    } else " ";

    if (pad_string.len == 0) {
        const result = env.allocator.dupe(u8, s) catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const total_len = @as(usize, @intCast(target_length));
    const pad_needed = total_len - s.len;
    var buf = std.ArrayList(u8).initCapacity(env.allocator, total_len) catch {
        return .{ .value = .{ .string = "" } };
    };
    buf.appendSlice(env.allocator, s) catch {};

    var written: usize = 0;
    while (written < pad_needed) {
        const remaining = pad_needed - written;
        const chunk = if (remaining < pad_string.len) pad_string[0..remaining] else pad_string;
        buf.appendSlice(env.allocator, chunk) catch {};
        written += chunk.len;
    }

    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "padEnd adds dots" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Breaded Mushrooms" }, .{ .integer = 25 }, .{ .string = "." } };
    const result = PadEnd(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("Breaded Mushrooms........", result.value.string);
}

test "padEnd default pad string is space" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Breaded Mushrooms" }, .{ .integer = 25 } };
    const result = PadEnd(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("Breaded Mushrooms        ", result.value.string);
}

test "padEnd targetLength less than string length" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 1 } };
    const result = PadEnd(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padEnd targetLength equal to string length" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 3 } };
    const result = PadEnd(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padEnd with empty pad string returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 10 }, .{ .string = "" } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "padEnd truncates padString from end" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "x" }, .{ .integer = 4 }, .{ .string = "abc" } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("xabc", result.value.string);
}

test "padEnd non-string returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 5 } };
    const result = PadEnd(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "padEnd no args returns empty" {
    const result = PadEnd(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "padEnd multiple repeats of pad string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hi" }, .{ .integer = 8 }, .{ .string = "xy" } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("hixyxyxy", result.value.string);
}

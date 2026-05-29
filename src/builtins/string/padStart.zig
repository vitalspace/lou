const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn PadStart(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
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

    var written: usize = 0;
    while (written < pad_needed) {
        const remaining = pad_needed - written;
        const chunk = if (remaining < pad_string.len) pad_string[0..remaining] else pad_string;
        buf.appendSlice(env.allocator, chunk) catch {};
        written += chunk.len;
    }

    buf.appendSlice(env.allocator, s) catch {};

    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "padStart with zeros" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "5" }, .{ .integer = 2 }, .{ .string = "0" } };
    const result = PadStart(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("05", result.value.string);
}

test "padStart with asterisks" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const fullNumber = "2034399002125581";
    const last4 = fullNumber[fullNumber.len - 4 ..];
    var args = [_]Types.Value{ .{ .string = last4 }, .{ .integer = fullNumber.len }, .{ .string = "*" } };
    const result = PadStart(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("************5581", result.value.string);
}

test "padStart default pad string is space" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "x" }, .{ .integer = 4 } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("   x", result.value.string);
}

test "padStart targetLength less than string length" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 1 } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padStart targetLength equal to string length" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 3 } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padStart with empty pad string returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 10 }, .{ .string = "" } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "padStart truncates padString from end" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "x" }, .{ .integer = 4 }, .{ .string = "abc" } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("abcx", result.value.string);
}

test "padStart non-string returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 5 } };
    const result = PadStart(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "padStart no args returns empty" {
    const result = PadStart(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "padStart multiple repeats of pad string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hi" }, .{ .integer = 8 }, .{ .string = "xy" } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("xyxyxyhi", result.value.string);
}

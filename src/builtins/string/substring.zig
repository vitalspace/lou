const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;
const Utils = @import("string_utils.zig");

pub fn Substring(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    const indexStart: i64 = if (args.len < 2) 0 else switch (args[1]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => 0,
        .null => 0,
        else => 0,
    };

    const indexEnd: i64 = if (args.len < 3) @as(i64, @intCast(s.len)) else switch (args[2]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => @as(i64, @intCast(s.len)),
        .null => @as(i64, @intCast(s.len)),
        else => @as(i64, @intCast(s.len)),
    };

    const cp_len = Utils.cpCount(s);
    var start: i64 = if (indexStart < 0) 0 else if (indexStart > cp_len) cp_len else indexStart;
    var end: i64 = if (indexEnd < 0) 0 else if (indexEnd > cp_len) cp_len else indexEnd;

    if (start > end) {
        const tmp = start;
        start = end;
        end = tmp;
    }

    if (start >= end) {
        const result = env.allocator.dupe(u8, "") catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const usize_start = Utils.cpToByte(s, start);
    const usize_end = Utils.cpToByte(s, end);
    const result = env.allocator.dupe(u8, s[usize_start..usize_end]) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "substring extracts between indices" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 1 }, .{ .integer = 3 } };
    const result = Substring(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("oz", result.value.string);
}

test "substring from start to end when no indexEnd" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 2 } };
    const result = Substring(&args, &env);
    try testing.expectEqualStrings("zilla", result.value.string);
}

test "substring swaps when start > end" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 3 }, .{ .integer = 1 } };
    const result = Substring(&args, &env);
    try testing.expectEqualStrings("oz", result.value.string);
}

test "substring negative clamped to 0" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = -1 }, .{ .integer = 3 } };
    const result = Substring(&args, &env);
    try testing.expectEqualStrings("Moz", result.value.string);
}

test "substring index beyond length clamped" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 0 }, .{ .integer = 100 } };
    const result = Substring(&args, &env);
    try testing.expectEqualStrings("Mozilla", result.value.string);
}

test "substring start equals end returns empty" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 3 }, .{ .integer = 3 } };
    const result = Substring(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "substring both negative returns empty" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = -5 }, .{ .integer = -2 } };
    const result = Substring(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "substring empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" }, .{ .integer = 0 } };
    const result = Substring(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "substring non-string returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 0 } };
    const result = Substring(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "substring no args returns empty" {
    const result = Substring(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "substring with float indices" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .float = 1.9 }, .{ .float = 4.2 } };
    const result = Substring(&args, &env);
    try testing.expectEqualStrings("ell", result.value.string);
}

test "substring with multi-byte characters" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "héllo" }, .{ .integer = 0 }, .{ .integer = 2 } };
    const result = Substring(&args, &env);
    try testing.expectEqualStrings("h\u{E9}", result.value.string);
}

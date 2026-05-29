const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;
const Utils = @import("string_utils.zig");

pub fn Substr(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    const start: i64 = if (args.len < 2) 0 else switch (args[1]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => 0,
        .null => 0,
        else => 0,
    };

    const cp_len = Utils.cpCount(s);
    const actual_start: i64 = if (start < 0) @max(0, cp_len + start) else @min(cp_len, start);

    if (actual_start >= cp_len) {
        const result = env.allocator.dupe(u8, "") catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    if (args.len < 3) {
        const byte_start = Utils.cpToByte(s, actual_start);
        const result = env.allocator.dupe(u8, s[byte_start..]) catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const length: i64 = switch (args[2]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => -1,
        .null => -1,
        else => -1,
    };

    if (length <= 0) {
        const result = env.allocator.dupe(u8, "") catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const actual_end = @min(cp_len, actual_start + length);
    const byte_start = Utils.cpToByte(s, actual_start);
    const byte_end = Utils.cpToByte(s, actual_end);

    if (byte_start >= byte_end) {
        const result = env.allocator.dupe(u8, "") catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const result = env.allocator.dupe(u8, s[byte_start..byte_end]) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "substr extracts with start and length" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 1 }, .{ .integer = 2 } };
    const result = Substr(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("oz", result.value.string);
}

test "substr extracts from start to end when no length" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 2 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("zilla", result.value.string);
}

test "substr negative start" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = -3 }, .{ .integer = 2 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("ll", result.value.string);
}

test "substr negative start beyond string clamps to 0" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = -10 }, .{ .integer = 2 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("Mo", result.value.string);
}

test "substr start beyond length returns empty" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 10 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "substr zero length returns empty" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 1 }, .{ .integer = 0 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "substr negative length returns empty" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 1 }, .{ .integer = -1 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "substr start 0 extracts whole string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 0 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("Mozilla", result.value.string);
}

test "substr length exceeding string clamps" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Mozilla" }, .{ .integer = 1 }, .{ .integer = 100 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("ozilla", result.value.string);
}

test "substr empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" }, .{ .integer = 0 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "substr non-string returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 0 } };
    const result = Substr(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "substr no args returns empty" {
    const result = Substr(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "substr with float indices" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .float = 1.9 }, .{ .float = 3.2 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("ell", result.value.string);
}

test "substr with multi-byte characters" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "héllo" }, .{ .integer = 0 }, .{ .integer = 2 } };
    const result = Substr(&args, &env);
    try testing.expectEqualStrings("h\u{E9}", result.value.string);
}

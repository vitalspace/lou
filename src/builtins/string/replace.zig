const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn Replace(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    if (args.len < 2) {
        const result = env.allocator.dupe(u8, s) catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const pattern = switch (args[1]) {
        .string => |p| p,
        else => {
            const result = env.allocator.dupe(u8, s) catch {
                return .{ .value = .{ .string = "" } };
            };
            env.owned_strings.append(env.allocator, result) catch {};
            return .{ .value = .{ .string = result } };
        },
    };

    const replacement = if (args.len >= 3) switch (args[2]) {
        .string => |r| r,
        else => "",
    } else "";

    if (pattern.len == 0) {
        const result = env.allocator.dupe(u8, s) catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    if (std.mem.indexOf(u8, s, pattern)) |idx| {
        const total_len = s.len - pattern.len + replacement.len;
        var buf = std.ArrayList(u8).initCapacity(env.allocator, total_len) catch {
            return .{ .value = .{ .string = "" } };
        };
        buf.appendSlice(env.allocator, s[0..idx]) catch {};
        buf.appendSlice(env.allocator, replacement) catch {};
        buf.appendSlice(env.allocator, s[idx + pattern.len ..]) catch {};
        const result = buf.toOwnedSlice(env.allocator) catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const result = env.allocator.dupe(u8, s) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "replace first occurrence only" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const p = "The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?";
    var args = [_]Types.Value{ .{ .string = p }, .{ .string = "dog" }, .{ .string = "monkey" } };
    const result = Replace(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("The quick brown fox jumps over the lazy monkey. If the dog barked, was it really lazy?", result.value.string);
}

test "replace no match returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "xyz" }, .{ .string = "foo" } };
    const result = Replace(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "replace empty pattern returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" }, .{ .string = "x" } };
    const result = Replace(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "replace with empty replacement" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = " world" }, .{ .string = "" } };
    const result = Replace(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "replace non-string pattern returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 42 }, .{ .string = "x" } };
    const result = Replace(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "replace only replaces first occurrence" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "aba" }, .{ .string = "a" }, .{ .string = "c" } };
    const result = Replace(&args, &env);
    try testing.expectEqualStrings("cba", result.value.string);
}

test "replace no args returns empty" {
    const result = Replace(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "replace non-string this returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "2" }, .{ .string = "x" } };
    const result = Replace(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "replace without replacement treats replacement as empty" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "ell" } };
    const result = Replace(&args, &env);
    try testing.expectEqualStrings("ho", result.value.string);
}

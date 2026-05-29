const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn ReplaceAll(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
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

    var buf = std.ArrayList(u8).initCapacity(env.allocator, s.len + 1) catch {
        return .{ .value = .{ .string = "" } };
    };
    defer buf.deinit(env.allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (std.mem.indexOf(u8, s[i..], pattern)) |match_idx| {
        buf.appendSlice(env.allocator, s[i..][0..match_idx]) catch {};
        buf.appendSlice(env.allocator, replacement) catch {};
        i += match_idx + pattern.len;
    } else {
        buf.appendSlice(env.allocator, s[i..]) catch {};
            break;
        }
    }
    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "replaceAll replaces all occurrences" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    const p = "The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?";
    var args = [_]Types.Value{ .{ .string = p }, .{ .string = "dog" }, .{ .string = "monkey" } };
    const result = ReplaceAll(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("The quick brown fox jumps over the lazy monkey. If the monkey barked, was it really lazy?", result.value.string);
}

test "replaceAll no match returns original" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "xyz" }, .{ .string = "foo" } };
    const result = ReplaceAll(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "replaceAll empty pattern returns original" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" }, .{ .string = "x" } };
    const result = ReplaceAll(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "replaceAll with empty replacement" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = " " }, .{ .string = "" } };
    const result = ReplaceAll(&args, &env);
    try testing.expectEqualStrings("helloworld", result.value.string);
}

test "replaceAll non-string pattern returns original" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 42 }, .{ .string = "x" } };
    const result = ReplaceAll(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "replaceAll multiple occurrences" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "aba" }, .{ .string = "a" }, .{ .string = "c" } };
    const result = ReplaceAll(&args, &env);
    try testing.expectEqualStrings("cbc", result.value.string);
}

test "replaceAll no args returns empty" {
    const result = ReplaceAll(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "replaceAll non-string this returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "2" }, .{ .string = "x" } };
    const result = ReplaceAll(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "replaceAll without replacement treats replacement as empty" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "l" } };
    const result = ReplaceAll(&args, &env);
    try testing.expectEqualStrings("heo", result.value.string);
}

test "replaceAll overlapping pattern does not re-replace" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "aaa" }, .{ .string = "aa" }, .{ .string = "b" } };
    const result = ReplaceAll(&args, &env);
    try testing.expectEqualStrings("ba", result.value.string);
}

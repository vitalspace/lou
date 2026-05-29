const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn CharAt(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |s| s,
        else => return .{ .value = .{ .string = "" } },
    };
    const index: i64 = if (args.len < 2) 0 else switch (args[1]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => 0,
        else => 0,
    };
    if (index < 0) return .{ .value = .{ .string = "" } };
    var count: i64 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        if (count == index) {
            var encoded: [4]u8 = undefined;
            const cp = std.unicode.utf8Decode(s[i..i+byte_len]) catch {
                return .{ .value = .{ .string = "" } };
            };
            const len = std.unicode.utf8Encode(cp, &encoded) catch unreachable;
            const result = env.allocator.dupe(u8, encoded[0..len]) catch {
                return .{ .value = .{ .string = "" } };
            };
            env.owned_strings.append(env.allocator, result) catch {};
            return .{ .value = .{ .string = result } };
        }
        i += byte_len;
        count += 1;
    }
    return .{ .value = .{ .string = "" } };
}

const testing = std.testing;

test "charAt positive index" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 1 } };
    const result = CharAt(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("e", result.value.string);
}

test "charAt no index defaults to 0" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" } };
    const result = CharAt(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("h", result.value.string);
}

test "charAt negative index returns empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = -1 } };
    const result = CharAt(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "charAt index beyond length returns empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hi" }, .{ .integer = 5 } };
    const result = CharAt(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "charAt empty string returns empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" }, .{ .integer = 0 } };
    const result = CharAt(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "charAt non-string returns empty string" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 0 } };
    const result = CharAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "charAt no args returns empty string" {
    const result = CharAt(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "charAt index 0 first char" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abcdef" }, .{ .integer = 3 } };
    const result = CharAt(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("d", result.value.string);
}

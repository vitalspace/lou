const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn ToLower(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |s| s,
        else => return .{ .value = .{ .void = {} } },
    };
    var buf = std.ArrayList(u8).initCapacity(env.allocator, s.len) catch {
        return .{ .value = .{ .void = {} } };
    };
    var i: usize = 0;
    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
            buf.append(env.allocator, s[i]) catch {};
            i += 1;
            continue;
        };
        const cp = std.unicode.utf8Decode(s[i .. i + byte_len]) catch {
            buf.appendSlice(env.allocator, s[i .. i + byte_len]) catch {};
            i += byte_len;
            continue;
        };
        const lower = switch (cp) {
            'A'...'Z' => cp + 32,
            else => cp,
        };
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(lower, &encoded) catch unreachable;
        buf.appendSlice(env.allocator, encoded[0..len]) catch {};
        i += byte_len;
    }
    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "toLowerCase converts uppercase letters" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "HELLO" } };
    const result = ToLower(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "toLowerCase no change for already lowercase" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" } };
    const result = ToLower(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "toLowerCase mixed case" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Hello World" } };
    const result = ToLower(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("hello world", result.value.string);
}

test "toLowerCase empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" } };
    const result = ToLower(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "toLowerCase numbers and symbols unchanged" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "FOO123!@#" } };
    const result = ToLower(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("foo123!@#", result.value.string);
}

test "toLowerCase non-string returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 } };
    const result = ToLower(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "toLowerCase no args returns empty string" {
    const result = ToLower(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("", result.value.string);
}

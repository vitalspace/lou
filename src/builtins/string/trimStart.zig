const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;
const Utils = @import("string_utils.zig");

pub fn TrimStart(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    var start: usize = 0;
    while (start < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[start]) catch {
            break;
        };
        if (start + byte_len > s.len) break;
        const cp = std.unicode.utf8Decode(s[start .. start + byte_len]) catch {
            break;
        };
        if (Utils.isWhitespaceChar(cp)) {
            start += byte_len;
        } else {
            break;
        }
    }

    const result = env.allocator.dupe(u8, s[start..]) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "trimStart removes leading whitespace" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "   Hello world!   " } };
    const result = TrimStart(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("Hello world!   ", result.value.string);
}

test "trimStart no leading whitespace" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Hello world!   " } };
    const result = TrimStart(&args, &env);
    try testing.expectEqualStrings("Hello world!   ", result.value.string);
}

test "trimStart all whitespace returns empty" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "   " } };
    const result = TrimStart(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "trimStart empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" } };
    const result = TrimStart(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "trimStart non-string returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 } };
    const result = TrimStart(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "trimStart no args returns empty" {
    const result = TrimStart(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

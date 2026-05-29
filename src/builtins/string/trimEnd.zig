const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;
const Utils = @import("string_utils.zig");

pub fn TrimEnd(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    var end: usize = s.len;
    while (end > 0) {
        var seq_start = end - 1;
        while (seq_start > 0 and (s[seq_start] & 0xC0) == 0x80) {
            seq_start -= 1;
        }
        const byte_len = std.unicode.utf8ByteSequenceLength(s[seq_start]) catch {
            break;
        };
        if (seq_start + byte_len != end) break;
        const cp = std.unicode.utf8Decode(s[seq_start..end]) catch {
            break;
        };
        if (Utils.isWhitespaceChar(cp)) {
            end = seq_start;
        } else {
            break;
        }
    }

    const result = env.allocator.dupe(u8, s[0..end]) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "trimEnd removes trailing whitespace" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "   Hello world!   " } };
    const result = TrimEnd(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("   Hello world!", result.value.string);
}

test "trimEnd no trailing whitespace" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "   Hello world!" } };
    const result = TrimEnd(&args, &env);
    try testing.expectEqualStrings("   Hello world!", result.value.string);
}

test "trimEnd all whitespace returns empty" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "   " } };
    const result = TrimEnd(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "trimEnd empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" } };
    const result = TrimEnd(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "trimEnd non-string returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 } };
    const result = TrimEnd(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "trimEnd no args returns empty" {
    const result = TrimEnd(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

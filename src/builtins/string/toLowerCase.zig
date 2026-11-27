const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;
const unicode_case = @import("unicode_case.zig");

/// Unicode Default Case Conversion treats capital sigma as final when it
/// follows a cased character and no cased character follows it.
fn isFinalSigma(s: []const u8, pos: usize, byte_len: usize) bool {
    if (pos == 0) return false;
    var start = pos - 1;
    while (start > 0 and (s[start] & 0xC0) == 0x80) start -= 1;
    const prev_len = std.unicode.utf8ByteSequenceLength(s[start]) catch return false;
    if (start + prev_len != pos) return false;
    const prev = std.unicode.utf8Decode(s[start..pos]) catch return false;
    if (!unicode_case.isCased(prev)) return false;

    const next_start = pos + byte_len;
    if (next_start >= s.len) return true;
    const next_len = std.unicode.utf8ByteSequenceLength(s[next_start]) catch return true;
    if (next_start + next_len > s.len) return true;
    const next = std.unicode.utf8Decode(s[next_start .. next_start + next_len]) catch return true;
    return !unicode_case.isCased(next);
}

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
        i += byte_len;
        if (cp < 0x80) {
            const lower: u21 = if (cp >= 'A' and cp <= 'Z') cp + 32 else cp;
            var encoded: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(lower, &encoded) catch unreachable;
            buf.appendSlice(env.allocator, encoded[0..len]) catch {};
            continue;
        }
        if (unicode_case.specialLower(cp)) |mapping| {
            buf.appendSlice(env.allocator, mapping) catch {};
            continue;
        }
        const lower: u21 = if (cp == 0x03A3 and isFinalSigma(s, i - byte_len, byte_len)) 0x03C2 else (unicode_case.lower(cp) orelse cp);
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(lower, &encoded) catch unreachable;
        buf.appendSlice(env.allocator, encoded[0..len]) catch {};
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
test "toLowerCase maps non-ASCII letters" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "ÜBER Café ΝΑΙ" } };
    const result = ToLower(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("über café ναι", result.value.string);
}

test "toLowerCase handles dotted I and final sigma" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "İSTANBUL ΟΣ ΣΣ" } };
    const result = ToLower(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("i\u{307}stanbul ος σς", result.value.string);
}

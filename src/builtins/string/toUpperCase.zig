const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;
const unicode_case = @import("unicode_case.zig");

pub fn ToUpper(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
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
            const upper: u21 = if (cp >= 'a' and cp <= 'z') cp - 32 else cp;
            var encoded: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(upper, &encoded) catch unreachable;
            buf.appendSlice(env.allocator, encoded[0..len]) catch {};
            continue;
        }
        if (unicode_case.specialUpper(cp)) |mapping| {
            buf.appendSlice(env.allocator, mapping) catch {};
            continue;
        }
        const upper = unicode_case.upper(cp) orelse cp;
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(upper, &encoded) catch unreachable;
        buf.appendSlice(env.allocator, encoded[0..len]) catch {};
    }
    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "toUpperCase converts lowercase letters" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" } };
    const result = ToUpper(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("HELLO", result.value.string);
}

test "toUpperCase no change for already uppercase" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "HELLO" } };
    const result = ToUpper(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("HELLO", result.value.string);
}

test "toUpperCase mixed case" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Hello World" } };
    const result = ToUpper(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("HELLO WORLD", result.value.string);
}

test "toUpperCase empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" } };
    const result = ToUpper(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "toUpperCase numbers and symbols unchanged" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "foo123!@#" } };
    const result = ToUpper(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("FOO123!@#", result.value.string);
}

test "toUpperCase non-string returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 } };
    const result = ToUpper(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "toUpperCase no args returns empty string" {
    const result = ToUpper(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("", result.value.string);
}
test "toUpperCase maps non-ASCII letters" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "über café ναι" } };
    const result = ToUpper(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("ÜBER CAFÉ ΝΑΙ", result.value.string);
}

test "toUpperCase expands sharp s and ligatures" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "straße ﬃ" } };
    const result = ToUpper(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("STRASSE FFI", result.value.string);
}

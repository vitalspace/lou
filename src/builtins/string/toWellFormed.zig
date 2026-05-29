const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn ToWellFormed(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    var i: usize = 0;
    var buf: ?std.ArrayList(u8) = null;

    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
            if (buf == null) {
                buf = std.ArrayList(u8).initCapacity(env.allocator, s.len) catch {
                    return .{ .value = .{ .string = "" } };
                };
                buf.?.appendSlice(env.allocator, s[0..i]) catch {};
            }
            buf.?.appendSlice(env.allocator, "\xEF\xBF\xBD") catch {};
            i += 1;
            continue;
        };
        if (i + byte_len > s.len) {
            if (buf == null) {
                buf = std.ArrayList(u8).initCapacity(env.allocator, s.len) catch {
                    return .{ .value = .{ .string = "" } };
                };
                buf.?.appendSlice(env.allocator, s[0..i]) catch {};
            }
            buf.?.appendSlice(env.allocator, "\xEF\xBF\xBD") catch {};
            i += 1;
            continue;
        }
        const is_surrogate = blk: {
            if (byte_len != 3) break :blk false;
            if (s[i] != 0xED) break :blk false;
            const b2 = s[i + 1];
            break :blk (b2 >= 0xA0 and b2 <= 0xBF);
        };
        if (is_surrogate) {
            if (buf == null) {
                buf = std.ArrayList(u8).initCapacity(env.allocator, s.len) catch {
                    return .{ .value = .{ .string = "" } };
                };
                buf.?.appendSlice(env.allocator, s[0..i]) catch {};
            }
            buf.?.appendSlice(env.allocator, "\xEF\xBF\xBD") catch {};
            i += byte_len;
        } else {
            if (buf) |*b| {
                b.appendSlice(env.allocator, s[i .. i + byte_len]) catch {};
            }
            i += byte_len;
        }
    }

    const result = if (buf) |*b|
        b.toOwnedSlice(env.allocator) catch {
            return .{ .value = .{ .string = "" } };
        }
    else
        env.allocator.dupe(u8, s) catch {
            return .{ .value = .{ .string = "" } };
        };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "toWellFormed well-formed string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" } };
    const result = ToWellFormed(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "toWellFormed empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" } };
    const result = ToWellFormed(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "toWellFormed lone high surrogate" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello\xED\xA0\x80" } };
    const result = ToWellFormed(&args, &env);
    try testing.expectEqualStrings("hello\xEF\xBF\xBD", result.value.string);
}

test "toWellFormed lone low surrogate" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "\xED\xB0\x80abc" } };
    const result = ToWellFormed(&args, &env);
    try testing.expectEqualStrings("\xEF\xBF\xBDabc", result.value.string);
}

test "toWellFormed surrogate pair unchanged" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "\xF0\x9F\x98\x80" } };
    const result = ToWellFormed(&args, &env);
    try testing.expectEqualStrings("\xF0\x9F\x98\x80", result.value.string);
}

test "toWellFormed non-string returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 } };
    const result = ToWellFormed(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "toWellFormed no args returns empty" {
    const result = ToWellFormed(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

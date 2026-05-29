const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn At(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    const s = switch (args[0]) {
        .string => |s| s,
        else => return .{ .value = .{ .void = {} } },
    };
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const index = switch (args[1]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => return .{ .value = .{ .void = {} } },
        else => return .{ .value = .{ .void = {} } },
    };
    var code_points: i64 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        i += byte_len;
        code_points += 1;
    }
    var resolved = index;
    if (resolved < 0) resolved = code_points + resolved;
    if (resolved < 0 or resolved >= code_points) return .{ .value = .{ .void = {} } };
    i = 0;
    var count: i64 = 0;
    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        if (count == resolved) {
            var encoded: [4]u8 = undefined;
            const cp = std.unicode.utf8Decode(s[i..i+byte_len]) catch {
                return .{ .value = .{ .void = {} } };
            };
            const len = std.unicode.utf8Encode(cp, &encoded) catch unreachable;
            const result = env.allocator.dupe(u8, encoded[0..len]) catch {
                return .{ .value = .{ .void = {} } };
            };
            env.owned_strings.append(env.allocator, result) catch {};
            return .{ .value = .{ .string = result } };
        }
        i += byte_len;
        count += 1;
    }
    return .{ .value = .{ .void = {} } };
}

const testing = std.testing;

test "at positive index" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 1 } };
    const result = At(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("e", result.value.string);
}

test "at negative index" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = -1 } };
    const result = At(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("o", result.value.string);
}

test "at out of range positive returns void" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hi" }, .{ .integer = 5 } };
    const result = At(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "at out of range negative returns void" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hi" }, .{ .integer = -5 } };
    const result = At(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "at empty string returns void" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" }, .{ .integer = 0 } };
    const result = At(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "at non-string returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 0 } };
    const result = At(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "at no args returns void" {
    const result = At(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "at first character" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 0 } };
    const result = At(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("h", result.value.string);
}

test "at negative index from middle" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abcdef" }, .{ .integer = -3 } };
    const result = At(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("d", result.value.string);
}

const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn CodePointAt(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    const s = switch (args[0]) {
        .string => |s| s,
        else => return .{ .value = .{ .void = {} } },
    };
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const pos = switch (args[1]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => return .{ .value = .{ .void = {} } },
        else => return .{ .value = .{ .void = {} } },
    };
    if (pos < 0) return .{ .value = .{ .void = {} } };
    var count: i64 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        if (count == pos) {
            const cp = std.unicode.utf8Decode(s[i..i+byte_len]) catch {
                return .{ .value = .{ .void = {} } };
            };
            return .{ .value = .{ .integer = @as(i64, @intCast(cp)) } };
        }
        i += byte_len;
        count += 1;
    }
    return .{ .value = .{ .void = {} } };
}

const testing = std.testing;

test "codePointAt positive position" {
    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 1 } };
    const result = CodePointAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 98), result.value.integer);
}

test "codePointAt position 0" {
    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 0 } };
    const result = CodePointAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 97), result.value.integer);
}

test "codePointAt position beyond length returns undefined" {
    var args = [_]Types.Value{ .{ .string = "hi" }, .{ .integer = 5 } };
    const result = CodePointAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "codePointAt negative position returns undefined" {
    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = -1 } };
    const result = CodePointAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "codePointAt empty string returns undefined" {
    var args = [_]Types.Value{ .{ .string = "" }, .{ .integer = 0 } };
    const result = CodePointAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "codePointAt non-string returns undefined" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 0 } };
    const result = CodePointAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "codePointAt no args returns undefined" {
    const result = CodePointAt(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "codePointAt no index returns undefined" {
    var args = [_]Types.Value{ .{ .string = "abc" } };
    const result = CodePointAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "codePointAt last position" {
    var args = [_]Types.Value{ .{ .string = "xyz" }, .{ .integer = 2 } };
    const result = CodePointAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 122), result.value.integer);
}

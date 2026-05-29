const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn CharCodeAt(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .float = std.math.nan(f64) } };
    const s = switch (args[0]) {
        .string => |s| s,
        else => return .{ .value = .{ .float = std.math.nan(f64) } },
    };
    const index: i64 = if (args.len < 2) 0 else switch (args[1]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => 0,
        else => 0,
    };
    if (index < 0) return .{ .value = .{ .float = std.math.nan(f64) } };
    var count: i64 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        if (count == index) {
            const cp = std.unicode.utf8Decode(s[i..i+byte_len]) catch {
                return .{ .value = .{ .float = std.math.nan(f64) } };
            };
            return .{ .value = .{ .integer = @as(i64, @intCast(cp)) } };
        }
        i += byte_len;
        count += 1;
    }
    return .{ .value = .{ .float = std.math.nan(f64) } };
}

const testing = std.testing;

test "charCodeAt positive index" {
    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 1 } };
    const result = CharCodeAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 98), result.value.integer);
}

test "charCodeAt no index defaults to 0" {
    var args = [_]Types.Value{ .{ .string = "abc" } };
    const result = CharCodeAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 97), result.value.integer);
}

test "charCodeAt negative index returns NaN" {
    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = -1 } };
    const result = CharCodeAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .float);
    try testing.expect(std.math.isNan(result.value.float));
}

test "charCodeAt index beyond length returns NaN" {
    var args = [_]Types.Value{ .{ .string = "hi" }, .{ .integer = 5 } };
    const result = CharCodeAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .float);
    try testing.expect(std.math.isNan(result.value.float));
}

test "charCodeAt empty string returns NaN" {
    var args = [_]Types.Value{ .{ .string = "" }, .{ .integer = 0 } };
    const result = CharCodeAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .float);
    try testing.expect(std.math.isNan(result.value.float));
}

test "charCodeAt non-string returns NaN" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 0 } };
    const result = CharCodeAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .float);
    try testing.expect(std.math.isNan(result.value.float));
}

test "charCodeAt no args returns NaN" {
    const result = CharCodeAt(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .float);
    try testing.expect(std.math.isNan(result.value.float));
}

test "charCodeAt uppercase A" {
    var args = [_]Types.Value{ .{ .string = "ABC" }, .{ .integer = 0 } };
    const result = CharCodeAt(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 65), result.value.integer);
}

const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn StartsWith(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .boolean = false } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .boolean = false } },
    };
    if (args.len < 2) return .{ .value = .{ .boolean = false } };
    const searchString = switch (args[1]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .boolean = false } },
    };
    const position: i64 = if (args.len < 3) 0 else switch (args[2]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => 0,
        .null => 0,
        else => 0,
    };
    if (searchString.len == 0) return .{ .value = .{ .boolean = true } };
    const pos: usize = if (position < 0) 0 else @as(usize, @intCast(position));
    if (pos > s.len) return .{ .value = .{ .boolean = false } };
    if (pos + searchString.len > s.len) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = std.mem.eql(u8, s[pos .. pos + searchString.len], searchString) } };
}

const testing = std.testing;

test "startsWith positive" {
    var args = [_]Types.Value{ .{ .string = "Saturday night plans" }, .{ .string = "Sat" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith negative" {
    var args = [_]Types.Value{ .{ .string = "Saturday night plans" }, .{ .string = "Sun" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith empty searchString" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith position shifts start" {
    var args = [_]Types.Value{ .{ .string = "Saturday night plans" }, .{ .string = "Sat" }, .{ .integer = 3 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith position finds later match" {
    var args = [_]Types.Value{ .{ .string = "Saturday night plans" }, .{ .string = "day" }, .{ .integer = 5 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith position at start of word" {
    var args = [_]Types.Value{ .{ .string = "Saturday night plans" }, .{ .string = "night" }, .{ .integer = 9 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith case sensitive" {
    var args = [_]Types.Value{ .{ .string = "Hello" }, .{ .string = "hello" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith position beyond length" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "h" }, .{ .integer = 10 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith negative position treated as 0" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "hello" }, .{ .integer = -1 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value.boolean);
}

test "startsWith non-string this returns false" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "4" } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith no args returns false" {
    const result = StartsWith(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

test "startsWith non-string searchString returns false" {
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 42 } };
    const result = StartsWith(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(!result.value.boolean);
}

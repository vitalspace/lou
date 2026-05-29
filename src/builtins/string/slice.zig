const std = @import("std");
const Types = @import("../../types/types.zig");
const Utils = @import("string_utils.zig");

pub fn Slice(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    const indexStart: i64 = if (args.len < 2) 0 else switch (args[1]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => 0,
        .null => 0,
        else => 0,
    };

    const indexEnd: i64 = if (args.len < 3) @as(i64, @intCast(s.len)) else switch (args[2]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .void => @as(i64, @intCast(s.len)),
        .null => @as(i64, @intCast(s.len)),
        else => @as(i64, @intCast(s.len)),
    };

    const cp_len = Utils.cpCount(s);
    var start = if (indexStart < 0) @max(0, cp_len + indexStart) else @min(cp_len, indexStart);
    const end = if (indexEnd < 0) @max(0, cp_len + indexEnd) else @min(cp_len, indexEnd);

    if (start > end) start = end;
    if (start >= end or start >= cp_len) {
        const result = env.allocator.dupe(u8, "") catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const usize_start = Utils.cpToByte(s, start);
    const usize_end = Utils.cpToByte(s, end);
    const result = env.allocator.dupe(u8, s[usize_start..usize_end]) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "slice extracts from start index" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "The quick brown fox jumps over the lazy dog." }, .{ .integer = 31 } };
    const result = Slice(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("the lazy dog.", result.value.string);
}

test "slice extracts between indices" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "The quick brown fox jumps over the lazy dog." }, .{ .integer = 4 }, .{ .integer = 19 } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("quick brown fox", result.value.string);
}

test "slice negative index from end" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "The quick brown fox jumps over the lazy dog." }, .{ .integer = -4 } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("dog.", result.value.string);
}

test "slice negative start and end" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "The quick brown fox jumps over the lazy dog." }, .{ .integer = -9 }, .{ .integer = -5 } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("lazy", result.value.string);
}

test "slice start beyond length returns empty" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 10 } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "slice start greater than end returns empty" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 3 }, .{ .integer = 1 } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "slice negative start beyond string clamps to 0" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = -10 } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "slice negative end clamps to 0" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 0 }, .{ .integer = -10 } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "slice no args returns whole string" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "slice non-string this returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 } };
    const result = Slice(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "slice no args at all returns empty" {
    const result = Slice(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "slice with float indices" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .float = 1.9 }, .{ .float = 4.2 } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("ell", result.value.string);
}

test "slice start 0 end 0 returns empty" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 0 }, .{ .integer = 0 } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "slice with multi-byte characters" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "héllo" }, .{ .integer = 0 }, .{ .integer = 2 } };
    const result = Slice(&args, &env);
    try testing.expectEqualStrings("h\u{E9}", result.value.string);
}

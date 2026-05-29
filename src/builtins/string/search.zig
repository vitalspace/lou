const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Search(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .integer = -1 } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .integer = -1 } },
    };
    if (args.len < 2) return .{ .value = .{ .integer = -1 } };

    const searchStr = switch (args[1]) {
        .string => |ss| ss,
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{i}) catch {
                return .{ .value = .{ .integer = -1 } };
            };
            const owned = env.allocator.dupe(u8, formatted) catch {
                return .{ .value = .{ .integer = -1 } };
            };
            defer env.allocator.free(owned);
            if (std.mem.indexOf(u8, s, owned)) |idx| {
                return .{ .value = .{ .integer = @as(i64, @intCast(idx)) } };
            }
            return .{ .value = .{ .integer = -1 } };
        },
        .float => |f| {
            if (std.math.isNan(f)) {
                if (std.mem.indexOf(u8, s, "NaN")) |idx| {
                    return .{ .value = .{ .integer = @as(i64, @intCast(idx)) } };
                }
                return .{ .value = .{ .integer = -1 } };
            }
            var buf: [64]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{f}) catch {
                return .{ .value = .{ .integer = -1 } };
            };
            const owned = env.allocator.dupe(u8, formatted) catch {
                return .{ .value = .{ .integer = -1 } };
            };
            defer env.allocator.free(owned);
            if (std.mem.indexOf(u8, s, owned)) |idx| {
                return .{ .value = .{ .integer = @as(i64, @intCast(idx)) } };
            }
            return .{ .value = .{ .integer = -1 } };
        },
        .boolean => |b| {
            const needle = if (b) "true" else "false";
            if (std.mem.indexOf(u8, s, needle)) |idx| {
                return .{ .value = .{ .integer = @as(i64, @intCast(idx)) } };
            }
            return .{ .value = .{ .integer = -1 } };
        },
        .null => {
            if (std.mem.indexOf(u8, s, "null")) |idx| {
                return .{ .value = .{ .integer = @as(i64, @intCast(idx)) } };
            }
            return .{ .value = .{ .integer = -1 } };
        },
        .void => {
            if (std.mem.indexOf(u8, s, "undefined")) |idx| {
                return .{ .value = .{ .integer = @as(i64, @intCast(idx)) } };
            }
            return .{ .value = .{ .integer = -1 } };
        },
        else => return .{ .value = .{ .integer = -1 } },
    };

    if (std.mem.indexOf(u8, s, searchStr)) |idx| {
        return .{ .value = .{ .integer = @as(i64, @intCast(idx)) } };
    }
    return .{ .value = .{ .integer = -1 } };
}

const testing = std.testing;

test "search finds substring" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "world" } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 6), result.value.integer);
}

test "search not found returns -1" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "xyz" } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "search empty string" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "search first occurrence" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello hello" }, .{ .string = "hello" } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "search case sensitive" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Hello" }, .{ .string = "hello" } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "search with integer arg" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc42def" }, .{ .integer = 42 } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 3), result.value.integer);
}

test "search non-string this returns -1" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "2" } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "search no args returns -1" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    const result = Search(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "search with boolean arg" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "it is true" }, .{ .boolean = true } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 6), result.value.integer);
}

test "search with null arg" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "value is null here" }, .{ .null = {} } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 9), result.value.integer);
}

test "search with undefined arg" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "undefined value" }, .{ .void = {} } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

test "search at position beyond string" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "h" } };
    const result = Search(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 0), result.value.integer);
}

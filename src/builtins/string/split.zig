const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn Split(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .void = {} } },
    };

    const separator: ?[]const u8 = if (args.len < 2) null else switch (args[1]) {
        .string => |sep| sep,
        .void => null,
        .null => null,
        else => null,
    };

    const limit: ?usize = if (args.len < 3) null else switch (args[2]) {
        .integer => |i| if (i < 0) null else @as(usize, @intCast(i)),
        .float => |f| if (f < 0) null else @as(usize, @intCast(@as(i64, @intFromFloat(f)))),
        .void => null,
        .null => null,
        else => null,
    };

    const arr = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };

    if (separator) |sep| {
        if (sep.len == 0) {
            if (s.len == 0) {
                const owned = env.allocator.dupe(u8, "") catch {
                    env.arrays.append(env.allocator, arr) catch {};
                    return .{ .value = .{ .array = arr } };
                };
                env.owned_strings.append(env.allocator, owned) catch {};
                arr.elements.append(env.allocator, .{ .string = owned }) catch {};
            } else {
                for (s, 0..) |_, i| {
                    if (limit) |lim| {
                        if (arr.elements.items.len >= lim) break;
                    }
                    const char = s[i .. i + 1];
                    const owned = env.allocator.dupe(u8, char) catch {
                        env.arrays.append(env.allocator, arr) catch {};
                        return .{ .value = .{ .array = arr } };
                    };
                    env.owned_strings.append(env.allocator, owned) catch {};
                    arr.elements.append(env.allocator, .{ .string = owned }) catch {};
                }
            }
        } else {
            var start: usize = 0;
            while (start <= s.len) {
                if (limit) |lim| {
                    if (arr.elements.items.len >= lim) break;
                }
                if (std.mem.indexOf(u8, s[start..], sep)) |idx| {
                    const segment = s[start .. start + idx];
                    const owned = env.allocator.dupe(u8, segment) catch {
                        env.arrays.append(env.allocator, arr) catch {};
                        return .{ .value = .{ .array = arr } };
                    };
                    env.owned_strings.append(env.allocator, owned) catch {};
                    arr.elements.append(env.allocator, .{ .string = owned }) catch {};
                    start += idx + sep.len;
                } else {
                    const segment = s[start..];
                    const owned = env.allocator.dupe(u8, segment) catch {
                        env.arrays.append(env.allocator, arr) catch {};
                        return .{ .value = .{ .array = arr } };
                    };
                    env.owned_strings.append(env.allocator, owned) catch {};
                    arr.elements.append(env.allocator, .{ .string = owned }) catch {};
                    break;
                }
            }
        }
    } else {
        const owned = env.allocator.dupe(u8, s) catch {
            return .{ .value = .{ .void = {} } };
        };
        env.owned_strings.append(env.allocator, owned) catch {};
        arr.elements.append(env.allocator, .{ .string = owned }) catch {};
    }

    env.arrays.append(env.allocator, arr) catch {};
    return .{ .value = .{ .array = arr } };
}

const testing = std.testing;

test "split by space" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "The quick brown fox jumps over the lazy dog." }, .{ .string = " " } };
    const result = Split(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqualStrings("The", result.value.array.elements.items[0].string);
    try testing.expectEqualStrings("fox", result.value.array.elements.items[3].string);
}

test "split empty string separator splits into chars" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" } };
    const result = Split(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 5), result.value.array.elements.items.len);
    try testing.expectEqualStrings("h", result.value.array.elements.items[0].string);
    try testing.expectEqualStrings("o", result.value.array.elements.items[4].string);
}

test "split without separator returns array with full string" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello world" } };
    const result = Split(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
    try testing.expectEqualStrings("hello world", result.value.array.elements.items[0].string);
}

test "split with limit" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "a b c d e" }, .{ .string = " " }, .{ .integer = 3 } };
    const result = Split(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try testing.expectEqualStrings("a", result.value.array.elements.items[0].string);
    try testing.expectEqualStrings("b", result.value.array.elements.items[1].string);
    try testing.expectEqualStrings("c", result.value.array.elements.items[2].string);
}

test "split with trailing separator produces empty string" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "a,b," }, .{ .string = "," } };
    const result = Split(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try testing.expectEqualStrings("a", result.value.array.elements.items[0].string);
    try testing.expectEqualStrings("b", result.value.array.elements.items[1].string);
    try testing.expectEqualStrings("", result.value.array.elements.items[2].string);
}

test "split empty string" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" }, .{ .string = "," } };
    const result = Split(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
    try testing.expectEqualStrings("", result.value.array.elements.items[0].string);
}

test "split non-string this returns void" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .integer = 42 } };
    const result = Split(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "split no args returns void" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    const result = Split(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "split separator at start produces empty first element" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = ",a,b" }, .{ .string = "," } };
    const result = Split(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try testing.expectEqualStrings("", result.value.array.elements.items[0].string);
    try testing.expectEqualStrings("a", result.value.array.elements.items[1].string);
    try testing.expectEqualStrings("b", result.value.array.elements.items[2].string);
}

test "split with void separator returns full string array" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .void = {} } };
    const result = Split(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
    try testing.expectEqualStrings("hello", result.value.array.elements.items[0].string);
}

test "split with negative limit ignores limit" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "a b c" }, .{ .string = " " }, .{ .integer = -1 } };
    const result = Split(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
}

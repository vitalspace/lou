const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

fn valueToString(val: Types.Value, allocator: std.mem.Allocator) ?[]const u8 {
    switch (val) {
        .string => |s| return allocator.dupe(u8, s) catch null,
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return null;
            return allocator.dupe(u8, s) catch null;
        },
        .float => |f| {
            if (std.math.isNan(f)) return allocator.dupe(u8, "NaN") catch null;
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return null;
            return allocator.dupe(u8, s) catch null;
        },
        .boolean => |b| {
            const s = if (b) "true" else "false";
            return allocator.dupe(u8, s) catch null;
        },
        .null => return allocator.dupe(u8, "null") catch null,
        .void => return allocator.dupe(u8, "undefined") catch null,
        else => return null,
    }
}

pub fn Match(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .null = {} } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .null = {} } },
    };
    const searchStr = valueToString(args[1], env.allocator) orelse {
        return .{ .value = .{ .null = {} } };
    };
    defer env.allocator.free(searchStr);
    if (std.mem.indexOf(u8, s, searchStr)) |idx| {
        const matched = s[idx .. idx + searchStr.len];
        const owned_match = env.allocator.dupe(u8, matched) catch {
            return .{ .value = .{ .null = {} } };
        };
        env.owned_strings.append(env.allocator, owned_match) catch {
            return .{ .value = .{ .null = {} } };
        };
        const owned_input = env.allocator.dupe(u8, s) catch {
            return .{ .value = .{ .null = {} } };
        };
        env.owned_strings.append(env.allocator, owned_input) catch {
            return .{ .value = .{ .null = {} } };
        };
        const arr = Ast.ArrayObject.initExtras(env.allocator) catch {
            return .{ .value = .{ .null = {} } };
        };
        arr.elements.append(env.allocator, .{ .string = owned_match }) catch {
            return .{ .value = .{ .null = {} } };
        };
        arr.extras.?.properties.put("index", .{ .integer = @as(i64, @intCast(idx)) }) catch {};
        arr.extras.?.properties.put("input", .{ .string = owned_input }) catch {};
        arr.extras.?.properties.put("groups", .{ .void = {} }) catch {};
        env.arrays.append(env.allocator, arr) catch {
            return .{ .value = .{ .null = {} } };
        };
        return .{ .value = .{ .array = arr } };
    }
    return .{ .value = .{ .null = {} } };
}

const testing = std.testing;

test "match finds substring" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "world" } };
    const result = Match(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
    try testing.expect(result.value.array.elements.items[0] == .string);
    try testing.expectEqualStrings("world", result.value.array.elements.items[0].string);
}

test "match not found returns null" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "xyz" } };
    const result = Match(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .null);
}

test "match empty search string at start" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "" } };
    const result = Match(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
    try testing.expectEqualStrings("", result.value.array.elements.items[0].string);
}

test "match with integer arg" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "hello42world" }, .{ .integer = 42 } };
    const result = Match(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqualStrings("42", result.value.array.elements.items[0].string);
}

test "match non-string this returns null" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "2" } };
    const result = Match(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .null);
}

test "match no args returns null" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    const result = Match(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .null);
}

test "match case sensitive" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "Hello" }, .{ .string = "hello" } };
    const result = Match(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .null);
}

test "match first occurrence" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "hello hello" }, .{ .string = "hello" } };
    const result = Match(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqualStrings("hello", result.value.array.elements.items[0].string);
}

test "match with boolean arg" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "hellotrueworld" }, .{ .boolean = true } };
    const result = Match(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqualStrings("true", result.value.array.elements.items[0].string);
}

test "match with null arg" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "hellonullworld" }, .{ .null = {} } };
    const result = Match(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqualStrings("null", result.value.array.elements.items[0].string);
}

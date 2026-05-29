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

pub fn MatchAll(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .void = {} } },
    };
    const searchStr = valueToString(args[1], env.allocator) orelse {
        return .{ .value = .{ .void = {} } };
    };
    defer env.allocator.free(searchStr);
    if (searchStr.len == 0) {
        return .{ .value = .{ .void = {} } };
    }
    const owned_input = env.allocator.dupe(u8, s) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, owned_input) catch {
        return .{ .value = .{ .void = {} } };
    };
    const results = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, results) catch {
        return .{ .value = .{ .void = {} } };
    };
    var pos: usize = 0;
    while (pos + searchStr.len <= s.len) {
        if (std.mem.indexOf(u8, s[pos..], searchStr)) |idx| {
            const match_pos = pos + idx;
            const matched = s[match_pos .. match_pos + searchStr.len];
            const owned_match = env.allocator.dupe(u8, matched) catch {
                return .{ .value = .{ .void = {} } };
            };
            env.owned_strings.append(env.allocator, owned_match) catch {
                return .{ .value = .{ .void = {} } };
            };
            const match_arr = Ast.ArrayObject.initExtras(env.allocator) catch {
                return .{ .value = .{ .void = {} } };
            };
            match_arr.elements.append(env.allocator, .{ .string = owned_match }) catch {
                return .{ .value = .{ .void = {} } };
            };
            match_arr.extras.?.properties.put("index", .{ .integer = @as(i64, @intCast(match_pos)) }) catch {};
            match_arr.extras.?.properties.put("input", .{ .string = owned_input }) catch {};
            match_arr.extras.?.properties.put("groups", .{ .void = {} }) catch {};
            env.arrays.append(env.allocator, match_arr) catch {
                return .{ .value = .{ .void = {} } };
            };
            results.elements.append(env.allocator, .{ .array = match_arr }) catch {
                return .{ .value = .{ .void = {} } };
            };
            pos = match_pos + searchStr.len;
        } else {
            break;
        }
    }
    var iter = Ast.ArrayIterator.initValues(env.allocator, results) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };
    return .{ .value = .{ .iterator = iter } };
}

const testing = std.testing;

test "matchAll finds all occurrences" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "test1test2" }, .{ .string = "test" } };
    const result = MatchAll(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .iterator);
    var iter = result.value.iterator;
    const r0 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(r0 == .js_object);
    try testing.expect(!r0.js_object.properties.get("done").?.boolean);
    const m0 = r0.js_object.properties.get("value").?.array;
    try testing.expectEqual(@as(usize, 1), m0.elements.items.len);
    try testing.expectEqualStrings("test", m0.elements.items[0].string);
    const r1 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(!r1.js_object.properties.get("done").?.boolean);
    const m1 = r1.js_object.properties.get("value").?.array;
    try testing.expectEqualStrings("test", m1.elements.items[0].string);
    const r2 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(r2.js_object.properties.get("done").?.boolean);
}

test "matchAll no matches returns empty iterator" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "xyz" } };
    const result = MatchAll(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .iterator);
    var iter = result.value.iterator;
    const r = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(r.js_object.properties.get("done").?.boolean);
}

test "matchAll with integer arg" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "a42b42c" }, .{ .integer = 42 } };
    const result = MatchAll(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .iterator);
    var iter = result.value.iterator;
    const r0 = iter.next(env.allocator, &env.arrays, &env.objects);
    const m0 = r0.js_object.properties.get("value").?.array;
    try testing.expectEqualStrings("42", m0.elements.items[0].string);
    const r1 = iter.next(env.allocator, &env.arrays, &env.objects);
    const m1 = r1.js_object.properties.get("value").?.array;
    try testing.expectEqualStrings("42", m1.elements.items[0].string);
}

test "matchAll non-string this returns void" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "2" } };
    const result = MatchAll(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "matchAll no args returns void" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    const result = MatchAll(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "matchAll overlapping does not overlap" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "ababa" }, .{ .string = "aba" } };
    const result = MatchAll(&args, &env);
    try testing.expect(result.value == .iterator);
    var iter = result.value.iterator;
    const r0 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(!r0.js_object.properties.get("done").?.boolean);
    const r1 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(r1.js_object.properties.get("done").?.boolean);
}

test "matchAll single match" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{ .{ .string = "hello world" }, .{ .string = "world" } };
    const result = MatchAll(&args, &env);
    try testing.expect(result.value == .iterator);
    var iter = result.value.iterator;
    const r0 = iter.next(env.allocator, &env.arrays, &env.objects);
    try testing.expect(!r0.js_object.properties.get("done").?.boolean);
    const m = r0.js_object.properties.get("value").?.array;
    try testing.expectEqualStrings("world", m.elements.items[0].string);
}

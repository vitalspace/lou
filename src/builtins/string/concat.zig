const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn appendValue(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, val: Types.Value) void {
    switch (val) {
        .string => |s| buf.appendSlice(allocator, s) catch {},
        .integer => |i| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
            buf.appendSlice(allocator, s) catch {};
        },
        .float => |f| {
            const s = if (std.math.isNan(f)) "NaN" else blk: {
                var tmp: [64]u8 = undefined;
                break :blk std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return;
            };
            buf.appendSlice(allocator, s) catch {};
        },
        .boolean => |b| buf.appendSlice(allocator, if (b) "true" else "false") catch {},
        .null, .void => buf.appendSlice(allocator, "null") catch {},
        else => buf.appendSlice(allocator, "null") catch {},
    }
}

pub fn Concat(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |s| s,
        else => return .{ .value = .{ .string = "" } },
    };
    if (args.len == 1) {
        const result = env.allocator.dupe(u8, s) catch {
            return .{ .value = .{ .string = "" } };
        };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }
    var buf = std.ArrayList(u8).initCapacity(env.allocator, s.len) catch {
        return .{ .value = .{ .string = "" } };
    };
    buf.appendSlice(env.allocator, s) catch {};
    for (args[1..]) |arg| {
        appendValue(&buf, env.allocator, arg);
    }
    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "concat two strings" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Hello" }, .{ .string = "World" } };
    const result = Concat(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("HelloWorld", result.value.string);
}

test "concat multiple strings" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "a" }, .{ .string = "b" }, .{ .string = "c" } };
    const result = Concat(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "concat no args returns copy" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" } };
    const result = Concat(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "concat empty string with value" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" }, .{ .string = "test" } };
    const result = Concat(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("test", result.value.string);
}

test "concat with integer arg" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "number: " }, .{ .integer = 42 } };
    const result = Concat(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("number: 42", result.value.string);
}

test "concat with boolean arg" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "is " }, .{ .boolean = true } };
    const result = Concat(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("is true", result.value.string);
}

test "concat with void (null) arg" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "val: " }, .{ .void = {} } };
    const result = Concat(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("val: null", result.value.string);
}

test "concat non-string this returns empty string" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "test" } };
    const result = Concat(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "concat no args at all returns empty string" {
    const result = Concat(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "concat with space separator" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Hello" }, .{ .string = " " }, .{ .string = "World" } };
    const result = Concat(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("Hello World", result.value.string);
}

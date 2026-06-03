const std = @import("std");
const Types = @import("../../types/types.zig");
const RegExpValue = Types.RegExpValue;

pub fn RegExpConstructor(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) {
        const regexp = RegExpValue.init(env.allocator, "", "") catch return .{ .value = .{ .void = {} } };
env.regexp_objects.append(env.allocator, regexp) catch {
            regexp.deinit();
            return .{ .value = .{ .void = {} } };
        };
        return .{ .value = .{ .regexp = regexp } };
    }

    const pattern: []const u8 = switch (args[0]) {
        .string => |s| s,
        .regexp => |r| r.pattern,
        else => return .{ .value = .{ .void = {} } },
    };

    const flags: []const u8 = if (args.len >= 2) switch (args[1]) {
        .string => |s| s,
        else => "",
    } else "";

    const regexp = RegExpValue.init(env.allocator, pattern, flags) catch return .{ .value = .{ .void = {} } };
    env.regexp_objects.append(env.allocator, regexp) catch {
        regexp.deinit();
        return .{ .value = .{ .void = {} } };
    };
    return .{ .value = .{ .regexp = regexp } };
}

const testing = std.testing;

test "RegExp constructor with string pattern" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "test" }, .{ .string = "g" } };
    const result = RegExpConstructor(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .regexp);
    try testing.expectEqualStrings("test", result.value.regexp.pattern);
    try testing.expect(result.value.regexp.global);
    try testing.expect(!result.value.regexp.ignore_case);
}

test "RegExp constructor with regexp arg" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    const re = try RegExpValue.init(testing.allocator, "abc", "i");
    defer re.deinit();
    var args = [_]Types.Value{ .{ .regexp = re } };
    const result = RegExpConstructor(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .regexp);
    try testing.expectEqualStrings("abc", result.value.regexp.pattern);
}

test "RegExp constructor no args" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    const result = RegExpConstructor(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .regexp);
    try testing.expectEqualStrings("", result.value.regexp.pattern);
}
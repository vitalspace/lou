const std = @import("std");
const Types = @import("../../types/types.zig");
const Env = @import("../../evaluator.zig").Environment;
const format = @import("format.zig");

pub fn Error(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    format.writeLine(env, .stderr, args, null);
    return .void;
}

test "error no args" {
    var env: Env = undefined;
    env = try Env.init(std.testing.allocator, null);
    defer env.deinit();
    const result = Error(&[_]Types.Value{}, &env);
    try std.testing.expect(result == .void);
}

test "error string" {
    var env: Env = undefined;
    env = try Env.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .string = "x" }};
    const result = Error(&args, &env);
    try std.testing.expect(result == .void);
}

test "error multiple" {
    var env: Env = undefined;
    env = try Env.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{
        .{ .string = "code" },
        .{ .integer = 7 },
        .{ .boolean = false },
    };
    const result = Error(&args, &env);
    try std.testing.expect(result == .void);
}
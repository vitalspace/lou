const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Clear(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = args;
    if (env.io) |io| {
        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.Writer.init(.stdout(), io, &buf);
        const out = &file_writer.interface;
        out.print("\x1B[2J\x1B[H", .{}) catch {};
        file_writer.flush() catch {};
    }
    return .void;
}

test "clear no args" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();
    const result = Clear(&[_]Types.Value{}, env);
    try std.testing.expect(result == .void);
}

test "clear with args" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .string = "ignored" }};
    const result = Clear(&args, env);
    try std.testing.expect(result == .void);
}
const std = @import("std");
const Types = @import("../../types/types.zig");
const Env = @import("../../evaluator.zig").Environment;
const ansi = @import("../../utils/ansi.zig");

fn printValueTo(out: anytype, value: Types.Value) void {
    switch (value) {
        .integer => |int_val| out.print("{s}{d}{s}", .{ ansi.Yellow, int_val, ansi.Reset }) catch {},
        .float => |f| out.print("{s}{d}{s}", .{ ansi.Yellow, f, ansi.Reset }) catch {},
        .string => |s| out.print("{s}\"{s}\"{s}", .{ ansi.Green, s, ansi.Reset }) catch {},
        .boolean => |b| out.print("{s}{}{s}", .{ ansi.Magenta, b, ansi.Reset }) catch {},
        .array => |a| {
            out.print("{s}[ {s}", .{ ansi.Gray, ansi.Reset }) catch {};
            for (a.elements.items, 0..) |elem, j| {
                if (j > 0) out.print("{s}, {s}", .{ ansi.Gray, ansi.Reset }) catch {};
                printValueTo(out, elem);
            }
            out.print("{s} ]{s}", .{ ansi.Gray, ansi.Reset }) catch {};
        },
        .void => out.print("{s}undefined{s}", .{ ansi.Dim, ansi.Reset }) catch {},
        .null => out.print("{s}null{s}", .{ ansi.Dim, ansi.Reset }) catch {},
        .object => out.print("{s}[object]{s}", .{ ansi.Cyan, ansi.Reset }) catch {},
        .closure => out.print("{s}[closure]{s}", .{ ansi.Cyan, ansi.Reset }) catch {},
        .iterator => out.print("{s}[object Array Iterator]{s}", .{ ansi.Yellow, ansi.Reset }) catch {},
        .js_object => |o| {
            out.print("{s}{{", .{ ansi.Gray }) catch {};
            var first = true;
            var it = o.properties.iterator();
            while (it.next()) |entry| {
                if (!first) out.print("{s},{s} ", .{ ansi.Gray, ansi.Reset }) catch {};
                first = false;
                out.print("{s}{s}:{s} ", .{ ansi.Cyan, entry.key_ptr.*, ansi.Reset }) catch {};
                printValueTo(out, entry.value_ptr.*);
            }
            out.print("{s}}}{s}", .{ ansi.Gray, ansi.Reset }) catch {};
        },
    }
}

pub fn Log(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (env.io) |io| {
        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.Writer.init(.stdout(), io, &buf);
        const out = &file_writer.interface;
        for (args, 0..) |arg, i| {
            if (i > 0) out.print(" ", .{}) catch {};
            switch (arg) {
                .string => |s| out.print("{s}", .{s}) catch {},
                else => printValueTo(out, arg),
            }
        }
        out.print("\n", .{}) catch {};
        file_writer.flush() catch {};
    }
    return .void;
}

pub fn flushLogForEnv(env: *Types.Environment) void {
    _ = env;
}

test "log no args" {
    var env: Env = undefined;
    env = try Env.init(std.testing.allocator, null);
    defer env.deinit();
    const result = Log(&[_]Types.Value{}, &env);
    try std.testing.expect(result == .void);
}

test "log number" {
    var env: Env = undefined;
    env = try Env.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .float = 42.0 }};
    const result = Log(&args, &env);
    try std.testing.expect(result == .void);
}

test "log string" {
    var env: Env = undefined;
    env = try Env.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .string = "hello" }};
    const result = Log(&args, &env);
    try std.testing.expect(result == .void);
}

test "log void" {
    var env: Env = undefined;
    env = try Env.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .void = {} }};
    const result = Log(&args, &env);
    try std.testing.expect(result == .void);
}

test "log multiple" {
    var env: Env = undefined;
    env = try Env.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{
        .{ .float = 1.0 },
        .{ .string = "world" },
        .{ .void = {} },
    };
    const result = Log(&args, &env);
    try std.testing.expect(result == .void);
}

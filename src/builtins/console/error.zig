const std = @import("std");
const Types = @import("../../types/types.zig");
const ansi = @import("../../utils/ansi.zig");

fn printValueTo(out: anytype, value: Types.Value, use_ansi: bool) void {
    const Y = if (use_ansi) ansi.Yellow else "";
    const G = if (use_ansi) ansi.Green else "";
    const C = if (use_ansi) ansi.Cyan else "";
    const M = if (use_ansi) ansi.Magenta else "";
    const D = if (use_ansi) ansi.Dim else "";
    const Gy = if (use_ansi) ansi.Gray else "";
    const Reset = if (use_ansi) ansi.Reset else "";

    switch (value) {
        .integer => |int_val| out.print("{s}{d}{s}", .{ Y, int_val, Reset }) catch {},
        .float => |f| {
            if (std.math.isNan(f)) {
                out.print("{s}NaN{s}", .{ Y, Reset }) catch {};
            } else {
                out.print("{s}{d}{s}", .{ Y, f, Reset }) catch {};
            }
        },
        .string => |s| out.print("{s}'{s}'{s}", .{ G, s, Reset }) catch {},
        .boolean => |b| out.print("{s}{}{s}", .{ M, b, Reset }) catch {},
        .array => |a| {
            if (a.elements.items.len == 0) {
                out.print("{s}[]{s}", .{ Gy, Reset }) catch {};
            } else {
                out.print("{s}[ {s}", .{ Gy, Reset }) catch {};
                for (a.elements.items, 0..) |elem, j| {
                    if (j > 0) out.print("{s}, {s}", .{ Gy, Reset }) catch {};
                    printValueTo(out, elem, use_ansi);
                }
                out.print("{s} ]{s}", .{ Gy, Reset }) catch {};
            }
        },
        .hole => out.print("{s}<empty>{s}", .{ D, Reset }) catch {},
        .void => out.print("{s}undefined{s}", .{ D, Reset }) catch {},
        .null => out.print("{s}null{s}", .{ D, Reset }) catch {},
        .object => out.print("{s}[object]{s}", .{ C, Reset }) catch {},
        .closure => out.print("{s}[closure]{s}", .{ C, Reset }) catch {},
        .function => out.print("{s}[function]{s}", .{ C, Reset }) catch {},
        .iterator => out.print("{s}[object Array Iterator]{s}", .{ Y, Reset }) catch {},
        .generator => out.print("{s}[generator]{s}", .{ C, Reset }) catch {},
        .symbol => |sym| out.print("{s}Symbol({s}){s}", .{ Y, sym.description, Reset }) catch {},
        .js_object => |o| {
            out.print("{s}{{ {s}", .{ Gy, Reset }) catch {};
            var first = true;
            var it = o.properties.iterator();
            while (it.next()) |entry| {
                if (!first) out.print("{s}, {s}", .{ Gy, Reset }) catch {};
                first = false;
                out.print("{s}{s}:{s} ", .{ C, entry.key_ptr.*, Reset }) catch {};
                printValueTo(out, entry.value_ptr.*, use_ansi);
            }
            out.print("{s} }}{s}", .{ Gy, Reset }) catch {};
        },
    }
}

pub fn Error(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (env.io) |io| {
        const use_ansi = ansi.supportsAnsi(io);
        const R = if (use_ansi) ansi.Red else "";
        const G = if (use_ansi) ansi.Green else "";
        const Reset = if (use_ansi) ansi.Reset else "";

        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.Writer.init(.stdout(), io, &buf);
        const out = &file_writer.interface;
        out.print("{s}[ERROR]{s} ", .{ R, Reset }) catch {};
        for (args, 0..) |arg, i| {
            if (i > 0) out.print(" ", .{}) catch {};
            switch (arg) {
                .string => |s| out.print("{s}{s}{s}", .{ G, s, Reset }) catch {},
                else => printValueTo(out, arg, use_ansi),
            }
        }
        out.print("\n", .{}) catch {};
        file_writer.flush() catch {};
    }
    return .void;
}

test "error no args" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();
    const result = Error(&[_]Types.Value{}, env);
    try std.testing.expect(result == .void);
}

test "error number" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .float = 42.0 }};
    const result = Error(&args, env);
    try std.testing.expect(result == .void);
}

test "error string" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .string = "hello" }};
    const result = Error(&args, env);
    try std.testing.expect(result == .void);
}

test "error void" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .void = {} }};
    const result = Error(&args, env);
    try std.testing.expect(result == .void);
}

test "error multiple" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{
        .{ .float = 1.0 },
        .{ .string = "world" },
        .{ .void = {} },
    };
    const result = Error(&args, env);
    try std.testing.expect(result == .void);
}
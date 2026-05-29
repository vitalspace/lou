const std = @import("std");
const Types = @import("../../types/types.zig");
const Env = @import("../../evaluator.zig").Environment;
const ansi = @import("../../utils/ansi.zig");

fn printValueTo(out: anytype, value: Types.Value, use_ansi: bool) void {
    const Y = if (use_ansi) ansi.Yellow else "";
    const G = if (use_ansi) ansi.Green else "";
    const C = if (use_ansi) ansi.Cyan else "";
    const M = if (use_ansi) ansi.Magenta else "";
    const D = if (use_ansi) ansi.Dim else "";
    const Gy = if (use_ansi) ansi.Gray else "";
    const R = if (use_ansi) ansi.Reset else "";

    switch (value) {
        .integer => |int_val| out.print("{s}{d}{s}", .{ Y, int_val, R }) catch {},
        .float => |f| {
            if (std.math.isNan(f)) {
                out.print("{s}NaN{s}", .{ Y, R }) catch {};
            } else {
                out.print("{s}{d}{s}", .{ Y, f, R }) catch {};
            }
        },
        .string => |s| out.print("{s}'{s}'{s}", .{ G, s, R }) catch {},
        .boolean => |b| out.print("{s}{}{s}", .{ M, b, R }) catch {},
        .array => |a| {
            if (a.elements.items.len == 0 and a.extras == null) {
                out.print("{s}[]{s}", .{ Gy, R }) catch {};
            } else {
                out.print("{s}[ {s}", .{ Gy, R }) catch {};
                for (a.elements.items, 0..) |elem, j| {
                    if (j > 0) out.print("{s}, {s}", .{ Gy, R }) catch {};
                    printValueTo(out, elem, use_ansi);
                }
                if (a.extras) |extras| {
                    const known_keys = [_][]const u8{ "index", "input", "groups" };
                    for (known_keys) |key| {
                        if (extras.properties.get(key)) |val| {
                            out.print("{s}, {s}{s}:{s} ", .{ Gy, C, key, R }) catch {};
                            printValueTo(out, val, use_ansi);
                        }
                    }
                    var it = extras.properties.iterator();
                    while (it.next()) |entry| {
                        var is_known = false;
                        for (known_keys) |k| {
                            if (std.mem.eql(u8, entry.key_ptr.*, k)) {
                                is_known = true;
                                break;
                            }
                        }
                        if (!is_known) {
                            out.print("{s}, {s}{s}:{s} ", .{ Gy, C, entry.key_ptr.*, R }) catch {};
                            printValueTo(out, entry.value_ptr.*, use_ansi);
                        }
                    }
                }
                out.print("{s} ]{s}", .{ Gy, R }) catch {};
            }
        },
        .void => out.print("{s}undefined{s}", .{ D, R }) catch {},
        .null => out.print("{s}null{s}", .{ D, R }) catch {},
        .object => out.print("{s}[object]{s}", .{ C, R }) catch {},
        .closure => out.print("{s}[closure]{s}", .{ C, R }) catch {},
        .function => out.print("{s}[function]{s}", .{ C, R }) catch {},
        .iterator => out.print("{s}[object Array Iterator]{s}", .{ Y, R }) catch {},
        .generator => out.print("{s}[generator]{s}", .{ C, R }) catch {},
        .symbol => |sym| out.print("{s}Symbol({s}){s}", .{ Y, sym.description, R }) catch {},
        .js_object => |o| {
            out.print("{s}{{ {s}", .{ Gy, R }) catch {};
            var first = true;
            var it = o.properties.iterator();
            while (it.next()) |entry| {
                if (!first) out.print("{s}, {s}", .{ Gy, R }) catch {};
                first = false;
                out.print("{s}{s}:{s} ", .{ C, entry.key_ptr.*, R }) catch {};
                printValueTo(out, entry.value_ptr.*, use_ansi);
            }
            out.print("{s} }}{s}", .{ Gy, R }) catch {};
        },
    }
}

pub fn Log(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (env.io) |io| {
        const use_ansi = ansi.supportsAnsi(io);
        const G = if (use_ansi) ansi.Green else "";
        const R = if (use_ansi) ansi.Reset else "";

        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.Writer.init(.stdout(), io, &buf);
        const out = &file_writer.interface;
        for (args, 0..) |arg, i| {
            if (i > 0) out.print(" ", .{}) catch {};
            switch (arg) {
                .string => |s| out.print("{s}{s}{s}", .{ G, s, R }) catch {},
                else => printValueTo(out, arg, use_ansi),
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

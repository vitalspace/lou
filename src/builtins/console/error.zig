const std = @import("std");
const Types = @import("../../types/types.zig");
const ansi = @import("../../utils/ansi.zig");

fn valueDisplayWidth(v: Types.Value) usize {
    return switch (v) {
        .integer => return 4,
        .float => return 12,
        .string => |s| 2 + s.len,
        .boolean => |b| if (b) 4 else 5,
        .void => return 9,
        .null => return 4,
        .hole => return 6,
        .array => return 10,
        else => return 8,
    };
}

fn shouldFormatArrayWrapped(a: *Types.ArrayObject) bool {
    var total: usize = 4;
    for (a.elements.items) |elem| {
        total += valueDisplayWidth(elem) + 2;
    }
    return total > 80;
}

fn printArrayInline(out: anytype, a: *Types.ArrayObject, use_ansi: bool, Gy: []const u8, R: []const u8, env: *Types.Environment) void {
    out.print("{s}[ {s}", .{ Gy, R }) catch {};
    for (a.elements.items, 0..) |elem, j| {
        if (j > 0) out.print("{s}, {s}", .{ Gy, R }) catch {};
        printValueTo(out, elem, use_ansi, env);
    }
    out.print("{s} ]{s}", .{ Gy, R }) catch {};
}

fn printArrayWrapped(out: anytype, a: *Types.ArrayObject, use_ansi: bool, Gy: []const u8, R: []const u8, env: *Types.Environment) void {
    out.print("{s}[ {s}", .{ Gy, R }) catch {};
    for (a.elements.items, 0..) |elem, j| {
        if (j > 0) {
            out.print(", ", .{}) catch {};
            if ((j % 6) == 0) {
                out.print("\n  ", .{}) catch {};
            }
        }
        printValueTo(out, elem, use_ansi, env);
    }
    out.print("\n{s}]{s}", .{ Gy, R }) catch {};
}

fn printValueTo(out: anytype, value: Types.Value, use_ansi: bool, env: *Types.Environment) void {
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
        .big_int => |b| {
            const digits = b.toString(env.allocator) catch return;
            defer env.allocator.free(digits);
            out.print("{s}{s}n{s}", .{ Y, digits, Reset }) catch {};
        },
        .string => |s| out.print("{s}'{s}'{s}", .{ G, s, Reset }) catch {},
        .boolean => |b| out.print("{s}{}{s}", .{ M, b, Reset }) catch {},
        .array => |a| {
            if (a.elements.items.len == 0) {
                out.print("{s}[]{s}", .{ Gy, Reset }) catch {};
            } else if (shouldFormatArrayWrapped(a)) {
                printArrayWrapped(out, a, use_ansi, Gy, Reset, env);
            } else {
                printArrayInline(out, a, use_ansi, Gy, Reset, env);
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
                 const key = entry.key_ptr.*;
                 var is_numeric_key: bool = false;
                 if (key.len > 0) {
                     var all_valid = true;
                     var has_digit = false;
                     for (key) |c| {
                         if (c >= '0' and c <= '9') {
                             has_digit = true;
                         } else if (c != '.') {
                             all_valid = false;
                             break;
                         }
                     }
                     is_numeric_key = all_valid and has_digit;
                 }
                 if (is_numeric_key) {
                     out.print("{s}'{s}':{s} ", .{ C, key, Reset }) catch {};
                 } else {
                     out.print("{s}{s}:{s} ", .{ C, key, Reset }) catch {};
                 }
                 printValueTo(out, entry.value_ptr.*, use_ansi, env);
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
                else => printValueTo(out, arg, use_ansi, env),
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
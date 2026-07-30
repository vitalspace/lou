const std = @import("std");
const Types = @import("../../types/types.zig");
const Env = @import("../../evaluator.zig").Environment;
const ansi = @import("../../utils/ansi.zig");

const MaxLineWidth = 80;

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
    return total > MaxLineWidth;
}

fn printArrayInline(out: anytype, a: *Types.ArrayObject, use_ansi: bool, Gy: []const u8, R: []const u8, C: []const u8, env: *Types.Environment) void {
    const D = if (use_ansi) ansi.Dim else "";
    out.print("{s}[ {s}", .{ Gy, R }) catch {};
    var hole_count: usize = 0;
    var first = true;
    for (a.elements.items) |elem| {
        if (elem == .hole) {
            hole_count += 1;
            continue;
        }
        if (hole_count > 0) {
            if (!first) out.print("{s}, {s}", .{ Gy, R }) catch {};
            if (hole_count == 1) {
                out.print("{s}<1 empty item>{s}", .{ D, R }) catch {};
            } else {
                out.print("{s}<{d} empty items>{s}", .{ D, hole_count, R }) catch {};
            }
            first = false;
            hole_count = 0;
        }
        if (!first) out.print("{s}, {s}", .{ Gy, R }) catch {};
        printValueTo(out, elem, use_ansi, env);
        first = false;
    }
    if (hole_count > 0) {
        if (!first) out.print("{s}, {s}", .{ Gy, R }) catch {};
        if (hole_count == 1) {
            out.print("{s}<1 empty item>{s}", .{ D, R }) catch {};
        } else {
            out.print("{s}<{d} empty items>{s}", .{ D, hole_count, R }) catch {};
        }
    }
    if (a.extras) |extras| {
        const known_keys = [_][]const u8{ "index", "input", "groups" };
        for (known_keys) |key| {
            if (extras.properties.get(key)) |val| {
                out.print("{s}, {s}{s}:{s} ", .{ Gy, C, key, R }) catch {};
                printValueTo(out, val, use_ansi, env);
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
                printValueTo(out, entry.value_ptr.*, use_ansi, env);
            }
        }
    }
    out.print("{s} ]{s}", .{ Gy, R }) catch {};
}

fn printArrayWrapped(out: anytype, a: *Types.ArrayObject, use_ansi: bool, Gy: []const u8, R: []const u8, env: *Types.Environment) void {
    const D = if (use_ansi) ansi.Dim else "";
    out.print("{s}[ {s}", .{ Gy, R }) catch {};
    var hole_count: usize = 0;
    var pos: usize = 0;
    var first = true;
    for (a.elements.items) |elem| {
        if (elem == .hole) {
            hole_count += 1;
            pos += 1;
            continue;
        }
        if (hole_count > 0) {
            if (!first) {
                out.print(", ", .{}) catch {};
                if ((pos % 6) == 0) {
                    out.print("\n  ", .{}) catch {};
                }
            }
            if (hole_count == 1) {
                out.print("{s}<1 empty item>{s}", .{ D, R }) catch {};
            } else {
                out.print("{s}<{d} empty items>{s}", .{ D, hole_count, R }) catch {};
            }
            first = false;
            hole_count = 0;
        }
        if (!first) {
            out.print(", ", .{}) catch {};
            if ((pos % 6) == 0) {
                out.print("\n  ", .{}) catch {};
            }
        }
        printValueTo(out, elem, use_ansi, env);
        first = false;
        pos += 1;
    }
    if (hole_count > 0) {
        if (!first) {
            out.print(", ", .{}) catch {};
            if ((pos % 6) == 0) {
                out.print("\n  ", .{}) catch {};
            }
        }
        if (hole_count == 1) {
            out.print("{s}<1 empty item>{s}", .{ D, R }) catch {};
        } else {
            out.print("{s}<{d} empty items>{s}", .{ D, hole_count, R }) catch {};
        }
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
    const R = if (use_ansi) ansi.Reset else "";

    switch (value) {
        .integer => |int_val| out.print("{s}{d}{s}", .{ Y, int_val, R }) catch {},
        .float => |f| {
            if (std.math.isNan(f)) {
                out.print("{s}NaN{s}", .{ Y, R }) catch {};
            } else if (std.math.isInf(f)) {
                out.print("{s}{s}{s}", .{ Y, if (f > 0) "Infinity" else "-Infinity", R }) catch {};
            } else {
                var tmp: [64]u8 = undefined;
                const w = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch unreachable;
                var end = w.len;
                if (std.mem.indexOfScalar(u8, tmp[0..end], '.')) |_| {
                    while (end > 1) {
                        const candidate = std.fmt.parseFloat(f64, tmp[0..end - 1]) catch break;
                        if (candidate != f) break;
                        end -= 1;
                    }
                }
                out.print("{s}{s}{s}", .{ Y, tmp[0..end], R }) catch {};
            }
        },
        .big_int => |b| {
            const digits = b.toString(env.allocator) catch return;
            defer env.allocator.free(digits);
            out.print("{s}{s}n{s}", .{ Y, digits, R }) catch {};
        },
        .string => |s| out.print("{s}\'{s}\'{s}", .{ G, s, R }) catch {},
        .boolean => |b| out.print("{s}{}{s}", .{ M, b, R }) catch {},
        .array => |a| {
            if (a.elements.items.len == 0 and a.extras == null) {
                out.print("{s}[]{s}", .{ Gy, R }) catch {};
            } else if (shouldFormatArrayWrapped(a)) {
                printArrayWrapped(out, a, use_ansi, Gy, R, env);
            } else {
                printArrayInline(out, a, use_ansi, Gy, R, C, env);
            }
        },
        .hole => out.print("{s}<empty>{s}", .{ D, R }) catch {},
        .void => out.print("{s}undefined{s}", .{ D, R }) catch {},
        .null => out.print("{s}null{s}", .{ D, R }) catch {},
        .object => out.print("{s}[object]{s}", .{ C, R }) catch {},
        .closure => out.print("{s}[closure]{s}", .{ C, R }) catch {},
        .function => out.print("{s}[function]{s}", .{ C, R }) catch {},
        .iterator => out.print("{s}[object Array Iterator]{s}", .{ Y, R }) catch {},
        .array_iterator => out.print("{s}[Array Iterator]{s}", .{ Y, R }) catch {},
        .regexp => |re| {
            var reg_buf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&reg_buf, "/{s}/{s}", .{re.pattern, re.flags}) catch "/regexp/";
            out.writeAll(s) catch {};
        },
        .generator => out.print("{s}[generator]{s}", .{ C, R }) catch {},
        .symbol => |sym| out.print("{s}Symbol({s}){s}", .{ Y, sym.description, R }) catch {},
.js_object => |o| {
             var count: usize = 0;
             var it = o.properties.iterator();
             while (it.next()) |_| { count += 1; }
             if (count == 0) {
                 out.print("{s}{{}}{s}", .{ Gy, R }) catch {};
             } else {
                 out.print("{s}{{ {s}", .{ Gy, R }) catch {};
                 var first = true;
                 var it2 = o.properties.iterator();
                 while (it2.next()) |entry| {
                     if (!first) out.print("{s}, {s}", .{ Gy, R }) catch {};
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
                         out.print("{s}'{s}':{s} ", .{ C, key, R }) catch {};
                     } else {
                         out.print("{s}{s}:{s} ", .{ C, key, R }) catch {};
                     }
                     printValueTo(out, entry.value_ptr.*, use_ansi, env);
                 }
                 out.print("{s} }}{s}", .{ Gy, R }) catch {};
             }
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
                .array => |a| {
                    const Gy = if (use_ansi) ansi.Gray else "";
                    const C = if (use_ansi) ansi.Cyan else "";
                    if (a.elements.items.len == 0 and a.extras == null) {
                        out.print("{s}[]{s}", .{ Gy, R }) catch {};
                    } else if (shouldFormatArrayWrapped(a)) {
                        printArrayWrapped(out, a, use_ansi, Gy, R, env);
                    } else {
                        printArrayInline(out, a, use_ansi, Gy, R, C, env);
                    }
                },
                else => printValueTo(out, arg, use_ansi, env),
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
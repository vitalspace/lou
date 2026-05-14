const std = @import("std");
const Types = @import("../../types/types.zig");

fn printValueTo(out: anytype, value: Types.Value) void {
    switch (value) {
        .integer => |int_val| out.print("{d}", .{int_val}) catch {},
        .float => |f| out.print("{d}", .{f}) catch {},
        .string => |s| out.print("{s}", .{s}) catch {},
        .boolean => |b| out.print("{}", .{b}) catch {},
        .array => |a| {
            out.print("[", .{}) catch {};
            for (a.elements.items, 0..) |elem, j| {
                if (j > 0) out.print(", ", .{}) catch {};
                switch (elem) {
                    .integer => |int_val| out.print("{d}", .{int_val}) catch {},
                    .float => |f| out.print("{d}", .{f}) catch {},
                    .string => |s| out.print("\"{s}\"", .{s}) catch {},
                    .boolean => |b| out.print("{}", .{b}) catch {},
                    .void => out.print("undefined", .{}) catch {},
                    .null => out.print("null", .{}) catch {},
                    .object => out.print("[object]", .{}) catch {},
                    .array => out.print("[array]", .{}) catch {},
                    .closure => out.print("[closure]", .{}) catch {},
                    .iterator => out.print("[object Array Iterator]", .{}) catch {},
                    .js_object => out.print("[object]", .{}) catch {},
                }
            }
            out.print("]", .{}) catch {};
        },
        .void => out.print("undefined", .{}) catch {},
        .null => out.print("null", .{}) catch {},
        .object => out.print("[object]", .{}) catch {},
        .closure => out.print("[closure]", .{}) catch {},
        .iterator => out.print("[object Array Iterator]", .{}) catch {},
        .js_object => |o| {
            out.print("{{", .{}) catch {};
            var first = true;
            var it = o.properties.iterator();
            while (it.next()) |entry| {
                if (!first) out.print(", ", .{}) catch {};
                first = false;
                out.print("{s}: ", .{entry.key_ptr.*}) catch {};
                printValueTo(out, entry.value_ptr.*);
            }
            out.print("}}", .{}) catch {};
        },
    }
}

pub fn Error(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (env.io) |io| {
        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.Writer.init(.stdout(), io, &buf);
        const out = &file_writer.interface;
        out.print("[ERROR] ", .{}) catch {};
        for (args, 0..) |arg, i| {
            if (i > 0) out.print(" ", .{}) catch {};
            printValueTo(out, arg);
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
const std = @import("std");
const Types = @import("../../types/types.zig");
const Env = @import("../../evaluator.zig").Environment;

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
                    .array => out.print("[ array ]", .{}) catch {},
                    .closure => out.print("[closure]", .{}) catch {},
                }
            }
            out.print("]", .{}) catch {};
        },
        .void => out.print("undefined", .{}) catch {},
        .null => out.print("null", .{}) catch {},
        .object => out.print("[object]", .{}) catch {},
        .closure => out.print("[closure]", .{}) catch {},
    }
}

pub fn Log(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (env.io) |io| {
        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.Writer.init(.stdout(), io, &buf);
        const out = &file_writer.interface;
        for (args, 0..) |arg, i| {
            if (i > 0) out.print(" ", .{}) catch {};
            printValueTo(out, arg);
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

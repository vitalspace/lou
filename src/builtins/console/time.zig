const std = @import("std");
const Types = @import("../../types/types.zig");

fn nowNs(env: *Types.Environment) i128 {
    if (env.io) |io| {
        const ts = std.Io.Timestamp.now(io, .awake);
        return ts.toNanoseconds();
    }
    return 0;
}

fn formatElapsedTo(out: anytype, label: []const u8, elapsed_ns: i128) void {
    if (elapsed_ns >= 60_000_000_000) {
        const min = @as(f64, @floatFromInt(elapsed_ns)) / 60_000_000_000.0;
        out.print("{s}: {d:.2}min\n", .{ label, min }) catch {};
    } else if (elapsed_ns >= 1_000_000_000) {
        const s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        out.print("{s}: {d:.3}s\n", .{ label, s }) catch {};
    } else if (elapsed_ns >= 1_000_000) {
        const ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
        out.print("{s}: {d:.2}ms\n", .{ label, ms }) catch {};
    } else if (elapsed_ns >= 1_000) {
        const us = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
        out.print("{s}: {d:.2}µs\n", .{ label, us }) catch {};
    } else {
        out.print("{s}: {d}ns\n", .{ label, elapsed_ns }) catch {};
    }
}

pub fn Time(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const label = if (args.len > 0 and args[0] == .string) args[0].string else "default";
    env.timers.put(label, nowNs(env)) catch {};
    return .void;
}

pub fn TimeEnd(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const label = if (args.len > 0 and args[0] == .string) args[0].string else "default";

    if (env.timers.get(label)) |start_time| {
        const elapsed_ns = nowNs(env) - start_time;
        if (env.io) |io| {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.Writer.initStreaming(.stdout(), io, &buf);
            const out = &file_writer.interface;
            formatElapsedTo(out, label, elapsed_ns);
            file_writer.flush() catch {};
        }
        _ = env.timers.remove(label);
    } else {
        if (env.io) |io| {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.Writer.initStreaming(.stdout(), io, &buf);
            const out = &file_writer.interface;
            out.print("Timer '{s}' does not exist\n", .{label}) catch {};
            file_writer.flush() catch {};
        }
    }
    return .void;
}

test "time no args" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();

    const result = Time(&[_]Types.Value{}, env);
    try std.testing.expect(result == .void);
}

test "time with label" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .string = "test_timer" }};
    const result = Time(&args, env);
    try std.testing.expect(result == .void);
    try std.testing.expect(env.timers.contains("test_timer"));
}

test "timeEnd no args" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();

    _ = Time(&[_]Types.Value{}, env);

    const result = TimeEnd(&[_]Types.Value{}, env);
    try std.testing.expect(result == .void);
    try std.testing.expect(!env.timers.contains("default"));
}

test "timeEnd with label" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .string = "test_timer" }};
    _ = Time(&args, env);

    const result = TimeEnd(&args, env);
    try std.testing.expect(result == .void);
    try std.testing.expect(!env.timers.contains("test_timer"));
}

test "timeEnd non-existent timer" {
    var env = try std.testing.allocator.create(@import("../../evaluator.zig").Environment);
    defer std.testing.allocator.destroy(env);
    env.* = try @import("../../evaluator.zig").Environment.init(std.testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .string = "non_existent" }};
    const result = TimeEnd(&args, env);
    try std.testing.expect(result == .void);
}
const std = @import("std");
const Types = @import("../../types/types.zig");
const format = @import("format.zig");
const table = @import("table.zig");

fn countLabel(args: []const Types.Value) []const u8 {
    if (args.len > 0 and args[0] == .string) return args[0].string;
    return "default";
}

fn optionUsize(value: Types.Value) ?usize {
    return switch (value) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        .float => |f| if (f >= 0 and std.math.isFinite(f)) @intFromFloat(f) else null,
        else => null,
    };
}

fn inspectOptions(value: ?Types.Value) format.InspectOptions {
    // Node's `console.dir` disables colors by default; only `console.log`
    // auto-detects a TTY.
    var opts = format.InspectOptions{ .colors = false };
    const obj = if (value) |v| switch (v) {
        .js_object => |o| o,
        else => return opts,
    } else return opts;

    if (obj.properties.get("depth")) |v| {
        if (v == .null) {
            opts.depth = null;
        } else if (optionUsize(v)) |d| {
            opts.depth = d;
        }
    }
    if (obj.properties.get("colors")) |v| {
        if (v == .boolean) opts.colors = v.boolean;
    }
    if (obj.properties.get("maxArrayLength")) |v| {
        if (v == .null) {
            opts.max_array_length = null;
        } else if (optionUsize(v)) |n| {
            opts.max_array_length = n;
        }
    }
    if (obj.properties.get("sorted")) |v| {
        if (v == .boolean) opts.sorted = v.boolean;
    }
    return opts;
}

pub fn Assert(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len > 0 and format.truthy(args[0])) return .void;
    if (args.len <= 1) {
        format.writeLine(env, .stderr, &[_]Types.Value{}, "Assertion failed");
    } else {
        format.writeLine(env, .stderr, args[1..], "Assertion failed: ");
    }
    return .void;
}

pub fn Count(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const label = countLabel(args);
    const root = env.root();
    const entry = root.console_counts.getOrPut(label) catch return .void;
    if (!entry.found_existing) entry.value_ptr.* = 0;
    entry.value_ptr.* +|= 1;
    format.writeFmt(env, .stdout, "{s}: {d}", .{ label, entry.value_ptr.* });
    return .void;
}

pub fn CountReset(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    // Node's no-argument form resets only the `default` label; an explicit
    // label resets that label. Unknown labels are ignored by Lou.
    const label = countLabel(args);
    _ = env.root().console_counts.remove(label);
    return .void;
}

pub fn Group(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len > 0) format.writeLine(env, .stdout, args, null);
    env.root().console_group_depth +|= 1;
    return .void;
}

pub fn GroupEnd(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = args;
    const root = env.root();
    if (root.console_group_depth > 0) root.console_group_depth -= 1;
    return .void;
}

pub fn Info(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    format.writeLine(env, .stdout, args, null);
    return .void;
}

pub fn Warn(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    format.writeLine(env, .stderr, args, null);
    return .void;
}

pub fn Debug(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    // Node's `console.debug` is an alias for `console.log` (stdout).
    format.writeLine(env, .stdout, args, null);
    return .void;
}

pub fn Trace(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    format.writeLine(env, .stderr, args, if (args.len == 0) "Trace" else "Trace: ");
    const root = env.root();
    var i = root.trace_frames.items.len;
    while (i > 0) {
        i -= 1;
        const frame = root.trace_frames.items[i];
        format.writeFmt(env, .stderr, "    at {s} ({s}:{d}:1)", .{ frame.name, root.source_name, frame.line });
    }
    return .void;
}

pub fn Dir(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const undefined_arg = [_]Types.Value{.{ .void = {} }};
    const values: []const Types.Value = if (args.len == 0) undefined_arg[0..] else args[0..1];
    const opts = inspectOptions(if (args.len > 1) args[1] else null);
    format.writeLineOptions(env, .stdout, values, null, opts);
    return .void;
}

pub fn Table(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return table.Table(args, env);
}

test "console.assert truthy is silent" {
    var env: Types.Environment = undefined;
    env = try Types.Environment.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .boolean = true }, .{ .string = "no" }};
    const result = Assert(&args, &env);
    try std.testing.expect(result == .void);
}

test "console.count increments and reset" {
    var env: Types.Environment = undefined;
    env = try Types.Environment.init(std.testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .string = "x" }};
    _ = Count(&args, &env);
    _ = Count(&args, &env);
    try std.testing.expectEqual(@as(u64, 2), env.console_counts.get("x").?);
    _ = CountReset(&args, &env);
    try std.testing.expect(env.console_counts.get("x") == null);
}

test "console.group depth" {
    var env: Types.Environment = undefined;
    env = try Types.Environment.init(std.testing.allocator, null);
    defer env.deinit();
    _ = Group(&[_]Types.Value{}, &env);
    _ = Group(&[_]Types.Value{}, &env);
    try std.testing.expectEqual(@as(u32, 2), env.console_group_depth);
    _ = GroupEnd(&[_]Types.Value{}, &env);
    try std.testing.expectEqual(@as(u32, 1), env.console_group_depth);
}

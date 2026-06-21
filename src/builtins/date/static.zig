const std = @import("std");
const Types = @import("../../types/types.zig");
const DateUtils = @import("date_utils.zig");
const Constructor = @import("constructor.zig");

/// `Date.now()` — current Unix epoch in milliseconds (Number).
pub fn DateNow(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = args;
    _ = env;
    const ts = Constructor.currentTimeMs();
    return .{ .value = .{ .float = @as(f64, @floatFromInt(ts)) } };
}

/// `Date.parse(string)` — parses an ISO 8601-ish date string and returns
/// its epoch-ms timestamp, or NaN if unparseable.
pub fn DateParse(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .float = std.math.nan(f64) } };
    const arg = args[0];
    if (arg != .string) return .{ .value = .{ .float = std.math.nan(f64) } };
    if (DateUtils.parseIsoDate(arg.string)) |ts| {
        return .{ .value = .{ .float = @as(f64, @floatFromInt(ts)) } };
    }
    return .{ .value = .{ .float = std.math.nan(f64) } };
}

/// `Date.UTC(year, month, day?, hours?, minutes?, seconds?, ms?)` —
/// builds a timestamp from UTC component arguments.
pub fn DateUTC(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2) return .{ .value = .{ .float = std.math.nan(f64) } };
    const year = toI64(args[0]);
    const month: u8 = @intCast(toI64(args[1]));
    const day: u8 = if (args.len >= 3) @intCast(toI64(args[2])) else 1;
    const hour: u8 = if (args.len >= 4) @intCast(toI64(args[3])) else 0;
    const minute: u8 = if (args.len >= 5) @intCast(toI64(args[4])) else 0;
    const second: u8 = if (args.len >= 6) @intCast(toI64(args[5])) else 0;
    const ms: u16 = if (args.len >= 7) @intCast(toI64(args[6])) else 0;
    const ts = DateUtils.timestampFromParts(year, month, day, hour, minute, second, ms);
    return .{ .value = .{ .float = @as(f64, @floatFromInt(ts)) } };
}

fn toI64(v: Types.Value) i64 {
    return switch (v) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => 0,
    };
}

test "Date.now returns a finite number" {
    const result = DateNow(&.{}, undefined);
    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == .float);
    try std.testing.expect(result.value.float > 0);
}

test "Date.parse - valid ISO" {
    var args = [_]Types.Value{.{ .string = "2024-01-15T10:30:00Z" }};
    const result = DateParse(&args, undefined);
    try std.testing.expect(result == .value);
    try std.testing.expectEqual(@as(i64, 1705314600000), @as(i64, @intFromFloat(result.value.float)));
}

test "Date.parse - invalid returns NaN" {
    var args = [_]Types.Value{.{ .string = "not a date" }};
    const result = DateParse(&args, undefined);
    try std.testing.expect(result == .value);
    try std.testing.expect(std.math.isNan(result.value.float));
}

test "Date.UTC - components" {
    var args = [_]Types.Value{
        .{ .integer = 2024 },
        .{ .integer = 0 }, // January
        .{ .integer = 15 },
        .{ .integer = 10 },
        .{ .integer = 30 },
    };
    const result = DateUTC(&args, undefined);
    try std.testing.expect(result == .value);
    try std.testing.expectEqual(@as(i64, 1705314600000), @as(i64, @intFromFloat(result.value.float)));
}

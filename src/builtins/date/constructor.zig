const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const DateUtils = @import("date_utils.zig");

/// `Date(...)` and `new Date(...)` constructor.
///
/// Signature (matches ECMAScript):
///   - `Date()` — returns the current timestamp as a string (not a Date
///     instance). For `new Date()` without args, returns a Date for "now".
///   - `Date(value)` where value is number-like — Date from epoch ms.
///   - `Date(string)` — Date from ISO 8601 string.
///   - `Date(year, month, day?, hours?, minutes?, seconds?, ms?)` — Date
///     from components. Month is 0-indexed (JS legacy).
pub fn DateConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const ts = currentTimeMs();
    const now_iso = DateUtils.parseIsoDate("1970-01-01") orelse 0; // placeholder

    const alloc = env.allocator;

    // Empty arg list — current time.
    if (args.len == 0) {
        const d = Types.DateValue.init(alloc, ts, "") catch return .{ .value = .{ .void = {} } };
        env.dates.append(alloc, d) catch {
            d.deinit();
            return .{ .value = .{ .void = {} } };
        };
        return .{ .value = .{ .date = d } };
    }

    // One argument: timestamp (number) or string.
    if (args.len == 1) {
        const arg = args[0];
        switch (arg) {
            .string => |s| {
                if (DateUtils.parseIsoDate(s)) |parsed| {
                    const d = Types.DateValue.init(alloc, parsed, s) catch return .{ .value = .{ .void = {} } };
                    env.dates.append(alloc, d) catch {
                        d.deinit();
                        return .{ .value = .{ .void = {} } };
                    };
                    return .{ .value = .{ .date = d } };
                }
                // Unrecognized string: return Invalid Date (NaN timestamp).
                const d = Types.DateValue.init(alloc, std.math.maxInt(i64), "") catch return .{ .value = .{ .void = {} } };
                env.dates.append(alloc, d) catch {
                    d.deinit();
                    return .{ .value = .{ .void = {} } };
                };
                return .{ .value = .{ .date = d } };
            },
            .integer, .float => {
                const ms: i64 = switch (arg) {
                    .integer => |i| i,
                    .float => |f| @as(i64, @intFromFloat(f)),
                    else => unreachable,
                };
                const d = Types.DateValue.init(alloc, ms, "") catch return .{ .value = .{ .void = {} } };
                env.dates.append(alloc, d) catch {
                    d.deinit();
                    return .{ .value = .{ .void = {} } };
                };
                return .{ .value = .{ .date = d } };
            },
            else => {
                // Coerce to number (e.g. Date object → its timestamp).
                const ms: i64 = switch (arg) {
                    .date => |d| d.timestamp_ms,
                    .integer => |i| i,
                    .float => |f| @as(i64, @intFromFloat(f)),
                    else => 0,
                };
                const d = Types.DateValue.init(alloc, ms, "") catch return .{ .value = .{ .void = {} } };
                env.dates.append(alloc, d) catch {
                    d.deinit();
                    return .{ .value = .{ .void = {} } };
                };
                return .{ .value = .{ .date = d } };
            },
        }
    }

    // 2+ args: year, month, day?, hours?, minutes?, seconds?, ms?
    const year = toInt(args[0]);
    const month: u8 = @intCast(toInt(args[1]));
    const day: u8 = if (args.len >= 3) @intCast(toInt(args[2])) else 1;
    const hour: u8 = if (args.len >= 4) @intCast(toInt(args[3])) else 0;
    const minute: u8 = if (args.len >= 5) @intCast(toInt(args[4])) else 0;
    const second: u8 = if (args.len >= 6) @intCast(toInt(args[5])) else 0;
    const millisecond: u16 = if (args.len >= 7) @intCast(toInt(args[6])) else 0;

    const ts2 = DateUtils.timestampFromLocalParts(year, month, day, hour, minute, second, millisecond);
    const d2 = Types.DateValue.init(alloc, ts2, "") catch return .{ .value = .{ .void = {} } };
    env.dates.append(alloc, d2) catch {
        d2.deinit();
        return .{ .value = .{ .void = {} } };
    };
    _ = now_iso;
    return .{ .value = .{ .date = d2 } };
}

fn toInt(v: Types.Value) i64 {
    return switch (v) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        .string => |s| std.fmt.parseInt(i64, s, 10) catch 0,
        else => 0,
    };
}

/// Current Unix epoch in milliseconds using `std.posix.system.clock_gettime`.
pub fn currentTimeMs() i64 {
    var ts: std.posix.timespec = .{ .sec = 0, .nsec = 0 };
    const rc = std.posix.system.clock_gettime(.REALTIME, &ts);
    if (rc != 0) return 0;
    return @as(i64, ts.sec) * 1000 + @divFloor(@as(i64, ts.nsec), 1_000_000);
}

const testing = std.testing;

test "DateConstructor - no args returns current time" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const before = currentTimeMs();
    const result = DateConstructor(&[_]Types.Value{}, &env);
    const after = currentTimeMs();

    try testing.expect(result == .value);
    try testing.expect(result.value == .date);
    const d = result.value.date;
    const ts = d.timestamp_ms;
    try testing.expect(ts >= before and ts <= after);
}

test "DateConstructor - from timestamp" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .float = 1705314600000.0 }};
    const result = DateConstructor(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 1705314600000), result.value.date.timestamp_ms);
}

test "DateConstructor - from components" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{
        .{ .integer = 2024 },
        .{ .integer = 0 }, // January
        .{ .integer = 15 },
        .{ .integer = 10 },
        .{ .integer = 30 },
    };
    const result = DateConstructor(&args, &env);
    try testing.expect(result == .value);
    // Local-time constructor: in UTC, components at 10:30 local = 10:30 UTC when
    // the system is at UTC+0. The exact value depends on the host timezone,
    // so we just verify the year/month/day components round-trip via getUTC*.
    const d = result.value.date;
    const p = DateUtils.partsFromTimestamp(d.timestamp_ms);
    try testing.expectEqual(@as(i32, 2024), p.year);
    try testing.expectEqual(@as(u8, 0), p.month);
    try testing.expectEqual(@as(u8, 15), p.day);
}

test "DateConstructor - from ISO string" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .string = "2024-01-15T10:30:00Z" }};
    const result = DateConstructor(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqual(@as(i64, 1705314600000), result.value.date.timestamp_ms);
}

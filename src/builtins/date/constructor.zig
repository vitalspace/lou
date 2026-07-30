const std = @import("std");
const Types = @import("../../types/types.zig");
const DateUtils = @import("date_utils.zig");

/// `Date(...)` and `new Date(...)` constructor.
///
/// Creates a `.js_object` with `@@type="Date"` and `timestamp_ms` as `.float`.
///
/// Signature (matches ECMAScript):
///   - `new Date()` — current time
///   - `new Date(value)` where value is number-like — Date from epoch ms
///   - `new Date(string)` — Date from ISO 8601 string
///   - `new Date(year, month, day?, hours?, minutes?, seconds?, ms?)` — Date
///     from components. Month is 0-indexed (JS legacy).
pub fn DateConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const alloc = env.allocator;

    // Create the js_object that will hold the Date data.
    const obj = Types.ObjectValue.init(alloc) catch return .{ .value = .{ .void = {} } };
    env.objects.append(alloc, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    obj.properties.put("@@type", .{ .string = "Date" }) catch {};

    // Empty arg list — current time.
    if (args.len == 0) {
        const ts = currentTimeMs();
        obj.properties.put("timestamp_ms", .{ .float = @as(f64, @floatFromInt(ts)) }) catch {};
        return .{ .value = .{ .js_object = obj } };
    }

    // One argument: timestamp (number) or string.
    if (args.len == 1) {
        const arg = args[0];
        switch (arg) {
            .string => |s| {
                if (DateUtils.parseIsoDate(s)) |parsed| {
                    obj.properties.put("timestamp_ms", .{ .float = @as(f64, @floatFromInt(parsed)) }) catch {};
                    return .{ .value = .{ .js_object = obj } };
                }
                // Unrecognized string: return Invalid Date (NaN timestamp).
                obj.properties.put("timestamp_ms", .{ .float = std.math.nan(f64) }) catch {};
                return .{ .value = .{ .js_object = obj } };
            },
            .integer, .float => {
                const ms: f64 = switch (arg) {
                    .integer => |i| @floatFromInt(i),
                    .float => |f| f,
                    else => unreachable,
                };
                obj.properties.put("timestamp_ms", .{ .float = ms }) catch {};
                return .{ .value = .{ .js_object = obj } };
            },
            else => {
                // Coerce to number (e.g. Date object → its timestamp).
                const ms: f64 = switch (arg) {
                    .js_object => |o| blk: {
                        if (o.properties.get("timestamp_ms")) |ts| {
                            break :blk switch (ts) {
                                .float => |f| f,
                                .integer => |i| @floatFromInt(i),
                                else => std.math.nan(f64),
                            };
                        }
                        break :blk std.math.nan(f64);
                    },
                    .integer => |i| @floatFromInt(i),
                    .float => |f| f,
                    else => std.math.nan(f64),
                };
                obj.properties.put("timestamp_ms", .{ .float = ms }) catch {};
                return .{ .value = .{ .js_object = obj } };
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
    obj.properties.put("timestamp_ms", .{ .float = @as(f64, @floatFromInt(ts2)) }) catch {};
    return .{ .value = .{ .js_object = obj } };
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
    try testing.expect(result.value == .js_object);
    const tag = result.value.js_object.properties.get("@@type");
    try testing.expect(tag != null);
    try testing.expectEqualStrings("Date", tag.?.string);
    const ts_val = result.value.js_object.properties.get("timestamp_ms");
    try testing.expect(ts_val != null);
    const ts = ts_val.?.float;
    try testing.expect(ts >= @as(f64, @floatFromInt(before)) and ts <= @as(f64, @floatFromInt(after)));
}

test "DateConstructor - from timestamp" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .float = 1705314600000.0 }};
    const result = DateConstructor(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .js_object);
    const ts_val = result.value.js_object.properties.get("timestamp_ms");
    try testing.expect(ts_val != null);
    try testing.expectEqual(@as(i64, 1705314600000), @as(i64, @intFromFloat(ts_val.?.float)));
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
    try testing.expect(result.value == .js_object);
    const ts_val = result.value.js_object.properties.get("timestamp_ms");
    try testing.expect(ts_val != null);
    const d_ts: i64 = @intFromFloat(ts_val.?.float);
    const p = DateUtils.partsFromTimestamp(d_ts);
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
    try testing.expect(result.value == .js_object);
    const ts_val = result.value.js_object.properties.get("timestamp_ms");
    try testing.expect(ts_val != null);
    try testing.expectEqual(@as(i64, 1705314600000), @as(i64, @intFromFloat(ts_val.?.float)));
}

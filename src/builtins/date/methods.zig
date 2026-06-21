const std = @import("std");
const Types = @import("../../types/types.zig");
const DateUtils = @import("date_utils.zig");

/// `Date.prototype.getTime()` → timestamp in ms.
pub fn DateGetTime(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    return .{ .value = .{ .float = @as(f64, @floatFromInt(args[0].date.timestamp_ms)) } };
}

/// `Date.prototype.valueOf()` → timestamp in ms (same as getTime).
pub fn DateValueOf(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateGetTime(args, env);
}

/// `Date.prototype.getFullYear()` → local-time year.
pub fn DateGetFullYear(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestampLocal(args[0].date.timestamp_ms);
    return .{ .value = .{ .integer = p.year } };
}

/// `Date.prototype.getMonth()` → local-time month, 0-11.
pub fn DateGetMonth(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestampLocal(args[0].date.timestamp_ms);
    return .{ .value = .{ .integer = p.month } };
}

/// `Date.prototype.getDate()` → local-time day of month, 1-31.
pub fn DateGetDate(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestampLocal(args[0].date.timestamp_ms);
    return .{ .value = .{ .integer = p.day } };
}

/// `Date.prototype.getDay()` → local-time day of week, 0 (Sun) - 6 (Sat).
pub fn DateGetDay(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestampLocal(args[0].date.timestamp_ms);
    return .{ .value = .{ .integer = p.weekday } };
}

/// `Date.prototype.getHours()` → local-time hour, 0-23.
pub fn DateGetHours(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestampLocal(args[0].date.timestamp_ms);
    return .{ .value = .{ .integer = p.hour } };
}

/// `Date.prototype.getMinutes()` → local-time minute, 0-59.
pub fn DateGetMinutes(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestampLocal(args[0].date.timestamp_ms);
    return .{ .value = .{ .integer = p.minute } };
}

/// `Date.prototype.getSeconds()` → local-time second, 0-59.
pub fn DateGetSeconds(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestampLocal(args[0].date.timestamp_ms);
    return .{ .value = .{ .integer = p.second } };
}

/// `Date.prototype.getMilliseconds()` → local-time millisecond, 0-999.
pub fn DateGetMilliseconds(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestampLocal(args[0].date.timestamp_ms);
    return .{ .value = .{ .integer = p.millisecond } };
}

/// `Date.prototype.getUTCFullYear()` → UTC year (same as getFullYear here).
pub fn DateGetUTCFullYear(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateGetFullYear(args, env);
}

/// `Date.prototype.getUTCMonth()` → UTC month (same as getMonth here).
pub fn DateGetUTCMonth(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateGetMonth(args, env);
}

/// `Date.prototype.getUTCDate()` → UTC day (same as getDate here).
pub fn DateGetUTCDate(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateGetDate(args, env);
}

/// `Date.prototype.getUTCDay()` → UTC weekday (same as getDay here).
pub fn DateGetUTCDay(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateGetDay(args, env);
}

/// `Date.prototype.getUTCHours()` → UTC hours (same as getHours here).
pub fn DateGetUTCHours(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateGetHours(args, env);
}

/// `Date.prototype.getUTCMinutes()` → UTC minutes (same as getMinutes here).
pub fn DateGetUTCMinutes(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateGetMinutes(args, env);
}

/// `Date.prototype.getUTCSeconds()` → UTC seconds (same as getSeconds here).
pub fn DateGetUTCSeconds(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateGetSeconds(args, env);
}

/// `Date.prototype.getUTCMilliseconds()` → UTC milliseconds.
pub fn DateGetUTCMilliseconds(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateGetMilliseconds(args, env);
}

/// `Date.prototype.setTime(ms)` — replaces the timestamp with `ms`.
pub fn DateSetTime(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const ms: i64 = switch (args[1]) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => 0,
    };
    args[0].date.timestamp_ms = ms;
    return .{ .value = .{ .float = @as(f64, @floatFromInt(ms)) } };
}

/// `Date.prototype.setFullYear(year, month?, day?)` — replaces the local
/// year (and optionally month and day) keeping the time-of-day intact.
pub fn DateSetFullYear(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const d = args[0].date;
    const p = DateUtils.partsFromTimestampLocal(d.timestamp_ms);
    const year = toI64(args[1]);
    const month: u8 = if (args.len >= 3) @intCast(toI64(args[2])) else p.month;
    const day: u8 = if (args.len >= 4) @intCast(toI64(args[3])) else p.day;
    d.timestamp_ms = DateUtils.timestampFromLocalParts(year, month, day, p.hour, p.minute, p.second, p.millisecond);
    return .{ .value = .{ .float = @as(f64, @floatFromInt(d.timestamp_ms)) } };
}

/// `Date.prototype.setMonth(month, day?)` — replaces the local month
/// (and optional day).
pub fn DateSetMonth(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const d = args[0].date;
    const p = DateUtils.partsFromTimestampLocal(d.timestamp_ms);
    const month: u8 = @intCast(toI64(args[1]));
    const day: u8 = if (args.len >= 3) @intCast(toI64(args[2])) else p.day;
    d.timestamp_ms = DateUtils.timestampFromLocalParts(p.year, month, day, p.hour, p.minute, p.second, p.millisecond);
    return .{ .value = .{ .float = @as(f64, @floatFromInt(d.timestamp_ms)) } };
}

/// `Date.prototype.setDate(day)` — replaces the local day of the month.
pub fn DateSetDate(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const d = args[0].date;
    const p = DateUtils.partsFromTimestampLocal(d.timestamp_ms);
    const day: u8 = @intCast(toI64(args[1]));
    d.timestamp_ms = DateUtils.timestampFromLocalParts(p.year, p.month, day, p.hour, p.minute, p.second, p.millisecond);
    return .{ .value = .{ .float = @as(f64, @floatFromInt(d.timestamp_ms)) } };
}

/// `Date.prototype.setHours(h, m?, s?, ms?)` — replaces the local hour
/// (and optional minutes/seconds/ms).
pub fn DateSetHours(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const d = args[0].date;
    const p = DateUtils.partsFromTimestampLocal(d.timestamp_ms);
    const hour: u8 = @intCast(toI64(args[1]));
    const minute: u8 = if (args.len >= 3) @intCast(toI64(args[2])) else p.minute;
    const second: u8 = if (args.len >= 4) @intCast(toI64(args[3])) else p.second;
    const ms: u16 = if (args.len >= 5) @intCast(toI64(args[4])) else p.millisecond;
    d.timestamp_ms = DateUtils.timestampFromLocalParts(p.year, p.month, p.day, hour, minute, second, ms);
    return .{ .value = .{ .float = @as(f64, @floatFromInt(d.timestamp_ms)) } };
}

/// `Date.prototype.setMinutes(m, s?, ms?)` — replaces the local minute.
pub fn DateSetMinutes(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const d = args[0].date;
    const p = DateUtils.partsFromTimestampLocal(d.timestamp_ms);
    const minute: u8 = @intCast(toI64(args[1]));
    const second: u8 = if (args.len >= 3) @intCast(toI64(args[2])) else p.second;
    const ms: u16 = if (args.len >= 4) @intCast(toI64(args[3])) else p.millisecond;
    d.timestamp_ms = DateUtils.timestampFromLocalParts(p.year, p.month, p.day, p.hour, minute, second, ms);
    return .{ .value = .{ .float = @as(f64, @floatFromInt(d.timestamp_ms)) } };
}

/// `Date.prototype.setSeconds(s, ms?)` — replaces the local second.
pub fn DateSetSeconds(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const d = args[0].date;
    const p = DateUtils.partsFromTimestampLocal(d.timestamp_ms);
    const second: u8 = @intCast(toI64(args[1]));
    const ms: u16 = if (args.len >= 3) @intCast(toI64(args[3])) else p.millisecond;
    _ = ms;
    d.timestamp_ms = DateUtils.timestampFromLocalParts(p.year, p.month, p.day, p.hour, p.minute, second, p.millisecond);
    return .{ .value = .{ .float = @as(f64, @floatFromInt(d.timestamp_ms)) } };
}

/// `Date.prototype.setMilliseconds(ms)` — replaces the local millisecond.
pub fn DateSetMilliseconds(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const d = args[0].date;
    const p = DateUtils.partsFromTimestampLocal(d.timestamp_ms);
    const ms: u16 = @intCast(toI64(args[1]));
    d.timestamp_ms = DateUtils.timestampFromLocalParts(p.year, p.month, p.day, p.hour, p.minute, p.second, ms);
    return .{ .value = .{ .float = @as(f64, @floatFromInt(d.timestamp_ms)) } };
}

fn toI64(v: Types.Value) i64 {
    return switch (v) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => 0,
    };
}

/// `Date.prototype.toISOString()` — formats as `YYYY-MM-DDTHH:MM:SS.sssZ`.
pub fn DateToISOString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestamp(args[0].date.timestamp_ms);
    const buf = std.fmt.allocPrint(env.allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{
        @as(u32, @intCast(p.year)), p.month + 1, p.day, p.hour, p.minute, p.second, p.millisecond,
    }) catch return .{ .value = .{ .void = {} } };
    env.owned_strings.append(env.allocator, buf) catch {};
    return .{ .value = .{ .string = buf } };
}

/// `Date.prototype.toDateString()` — formats as `Day Mon DD YYYY` (UTC).
pub fn DateToDateString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestamp(args[0].date.timestamp_ms);
    const buf = std.fmt.allocPrint(env.allocator, "{s} {s} {d:0>2} {d}", .{
        DateUtils.DAY_NAMES[p.weekday],
        DateUtils.MONTH_NAMES[p.month],
        p.day,
        p.year,
    }) catch return .{ .value = .{ .void = {} } };
    env.owned_strings.append(env.allocator, buf) catch {};
    return .{ .value = .{ .string = buf } };
}

/// `Date.prototype.toTimeString()` — formats as `HH:MM:SS GMT+0000` (UTC).
pub fn DateToTimeString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const p = DateUtils.partsFromTimestamp(args[0].date.timestamp_ms);
    const buf = std.fmt.allocPrint(env.allocator, "{d:0>2}:{d:0>2}:{d:0>2} GMT+0000", .{
        p.hour, p.minute, p.second,
    }) catch return .{ .value = .{ .void = {} } };
    env.owned_strings.append(env.allocator, buf) catch {};
    return .{ .value = .{ .string = buf } };
}

/// `Date.prototype.toString()` — combined `toDateString() + " " + toTimeString()`.
pub fn DateToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1 or args[0] != .date) return .{ .value = .{ .void = {} } };
    const ds = DateToDateString(args, env);
    const ts = DateToTimeString(args, env);
    if (ds != .value or ts != .value) return .{ .value = .{ .void = {} } };
    const buf = std.fmt.allocPrint(env.allocator, "{s} {s}", .{ ds.value.string, ts.value.string }) catch return .{ .value = .{ .void = {} } };
    env.owned_strings.append(env.allocator, buf) catch {};
    return .{ .value = .{ .string = buf } };
}

/// `Date.prototype.toLocaleDateString()` — same as `toDateString()` here
/// (no locale awareness).
pub fn DateToLocaleDateString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateToDateString(args, env);
}

/// `Date.prototype.toLocaleTimeString()` — same as `toTimeString()` here.
pub fn DateToLocaleTimeString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateToTimeString(args, env);
}

/// `Date.prototype.toLocaleString()` — combined, no locale.
pub fn DateToLocaleString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateToString(args, env);
}

/// `Date.prototype.toJSON()` — same as `toISOString()`.
pub fn DateToJSON(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return DateToISOString(args, env);
}

test "Date prototype getters" {
    const allocator = std.testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    var date = Types.DateValue{
        .allocator = allocator,
        .timestamp_ms = 1705314600000, // 2024-01-15T10:30:00Z
        .iso_string = "",
    };

    var args = [_]Types.Value{.{ .date = &date }};

    const yr = DateGetFullYear(&args, &env);
    try std.testing.expectEqual(@as(i32, 2024), yr.value.integer);

    const mo = DateGetMonth(&args, &env);
    try std.testing.expectEqual(@as(u8, 0), @as(u8, @intCast(mo.value.integer)));

    const d = DateGetDate(&args, &env);
    try std.testing.expectEqual(@as(u8, 15), @as(u8, @intCast(d.value.integer)));

    const h = DateGetHours(&args, &env);
    try std.testing.expectEqual(@as(u8, 10), @as(u8, @intCast(h.value.integer)));

    const m = DateGetMinutes(&args, &env);
    try std.testing.expectEqual(@as(u8, 30), @as(u8, @intCast(m.value.integer)));

    const iso = DateToISOString(&args, &env);
    try std.testing.expectEqualStrings("2024-01-15T10:30:00.000Z", iso.value.string);
}

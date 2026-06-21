//! Date/time math helpers for the `Date` builtin.
//!
//! Lou uses UTC throughout for `Date` (no local timezone support yet). The
//! conversions here match the JS `Date.UTC(...)` constructor and the
//! `getUTC*` family of getters.
//!
//! The conversion from days-since-epoch to (year, month, day) uses Howard
//! Hinnant's `civil_from_days` algorithm (public domain, ISO C++ proposal
//! based). The reverse direction (`days_from_civil`) is also Hinnant's.

const std = @import("std");

/// Number of milliseconds in one day.
pub const MS_PER_DAY: i64 = 86_400_000;

/// Number of milliseconds in one hour.
pub const MS_PER_HOUR: i64 = 3_600_000;

/// Number of milliseconds in one minute.
pub const MS_PER_MINUTE: i64 = 60_000;

/// Day-of-week names (index 0 = Sunday, matching JS `getDay()`).
pub const DAY_NAMES = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };

/// Month names (index 0 = January, matching JS `getMonth()`).
pub const MONTH_NAMES = [_][]const u8{
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
};

/// Local-time date components. Use `partsFromTimestampLocal` to compute
/// these from a UTC timestamp by applying the system's local timezone offset.
pub const LocalParts = struct {
    year: i32,
    month: u8, // 0-11
    day: u8, // 1-31
    weekday: u8, // 0-6 (Sun=0)
    hour: u8, // 0-23
    minute: u8, // 0-59
    second: u8, // 0-59
    millisecond: u16, // 0-999
    timezone_offset_minutes: i32, // minutes west of UTC (positive = behind UTC)
};

/// Return the system's local timezone offset in minutes west of UTC.
/// Currently returns 0 (UTC) — proper local timezone detection requires
/// platform-specific syscalls (e.g. `gettimeofday(tz)` on POSIX) that
/// would pull in libc. Lou tests skip local-timezone-dependent outputs
/// in the compat suite.
pub fn localTimezoneOffsetMinutes() i32 {
    return 0;
}

/// Split a Unix-epoch millisecond timestamp into local date/time parts.
/// Applies the system's local timezone offset (minutes west of UTC) so the
/// returned components match what `Date.getFullYear()` etc. would return
/// in JS when running on the same system.
pub fn partsFromTimestampLocal(ts_ms: i64) LocalParts {
    const offset_min = localTimezoneOffsetMinutes();
    // offset_min is "minutes west" (positive west). To convert UTC to local
    // we SUBTRACT (so for UTC-6: local = UTC - (-360min) = UTC + 360min? no).
    // JS: local = UTC + (-minuteswest). For UTC-6 (minuteswest=360), local = UTC - 6h.
    const local_ts = ts_ms - (@as(i64, offset_min) * 60 * 1000);
    const utc = partsFromTimestamp(local_ts);
    return .{
        .year = utc.year,
        .month = utc.month,
        .day = utc.day,
        .weekday = utc.weekday,
        .hour = utc.hour,
        .minute = utc.minute,
        .second = utc.second,
        .millisecond = utc.millisecond,
        .timezone_offset_minutes = offset_min,
    };
}

/// Build a timestamp from local-time parts (for setters and constructor
/// with `(year, month, ...)` arguments). The components are interpreted in
/// the system's local timezone. Mirrors JS two-digit year extension
/// (`0–99` map to `1900–1999`).
pub fn timestampFromLocalParts(year: i64, month: u8, day: u8, hour: u8, minute: u8, second: u8, millisecond: u16) i64 {
    const local_ts = timestampFromParts(year, month, day, hour, minute, second, millisecond);
    const offset_min = localTimezoneOffsetMinutes();
    return local_ts + (@as(i64, offset_min) * 60 * 1000);
}

/// Split a Unix-epoch millisecond timestamp into UTC date/time parts.
pub fn partsFromTimestamp(ts_ms: i64) LocalParts {
    // Work in whole days to avoid floating-point wobble.
    const days = @divFloor(ts_ms, MS_PER_DAY);
    const ms_in_day = ts_ms - days * MS_PER_DAY;

    const hour: i64 = @divFloor(ms_in_day, MS_PER_HOUR);
    const minute: i64 = @divFloor(ms_in_day - hour * MS_PER_HOUR, MS_PER_MINUTE);
    const second: i64 = @divFloor(ms_in_day - hour * MS_PER_HOUR - minute * MS_PER_MINUTE, 1000);
    const ms: i64 = ms_in_day - hour * MS_PER_HOUR - minute * MS_PER_MINUTE - second * 1000;

    const civil = civilFromDays(days);
    return .{
        .year = civil.year,
        .month = @intCast(civil.month - 1), // JS month is 0-indexed
        .day = @intCast(civil.day),
        .weekday = @intCast(@mod(days + 4, 7)), // 1970-01-01 was Thursday (4)
        .hour = @intCast(hour),
        .minute = @intCast(minute),
        .second = @intCast(second),
        .millisecond = @intCast(ms),
        .timezone_offset_minutes = 0,
    };
}

/// Build a timestamp from UTC parts (for setters and constructor with
/// (year, month, ...) arguments). Mirrors JS two-digit year extension
/// (`0–99` map to `1900–1999`).
pub fn timestampFromParts(year: i64, month: u8, day: u8, hour: u8, minute: u8, second: u8, millisecond: u16) i64 {
    const adjusted_year: i64 = if (year >= 0 and year <= 99) year + 1900 else year;
    const days = daysFromCivil(adjusted_year, month + 1, day); // convert from JS 0-based to civil 1-based
    return days * MS_PER_DAY +
        @as(i64, hour) * MS_PER_HOUR +
        @as(i64, minute) * MS_PER_MINUTE +
        @as(i64, second) * 1000 +
        @as(i64, millisecond);
}

/// Parse a subset of ISO 8601 strings (`YYYY-MM-DDTHH:MM:SS[.sss][Z]`).
/// Returns null if the input doesn't match the supported shape.
pub fn parseIsoDate(s: []const u8) ?i64 {
    // Accept "YYYY-MM-DD" and "YYYY-MM-DDTHH:MM:SS" / "YYYY-MM-DDTHH:MM:SS.sss",
    // both with optional trailing "Z".
    var i: usize = 0;
    const year = parseIntNS(s, &i, 4) orelse return null;
    if (i >= s.len or s[i] != '-') return null;
    i += 1;
    const month = parseIntNS(s, &i, 2) orelse return null;
    if (i >= s.len or s[i] != '-') return null;
    i += 1;
    const day = parseIntNS(s, &i, 2) orelse return null;

    var hour: u8 = 0;
    var minute: u8 = 0;
    var second: u8 = 0;
    var millisecond: u16 = 0;

    if (i < s.len and s[i] == 'T') {
        i += 1;
        hour = @intCast(parseIntNS(s, &i, 2) orelse return null);
        if (i >= s.len or s[i] != ':') return null;
        i += 1;
        minute = @intCast(parseIntNS(s, &i, 2) orelse return null);
        if (i >= s.len or s[i] != ':') return null;
        i += 1;
        second = @intCast(parseIntNS(s, &i, 2) orelse return null);
        if (i < s.len and s[i] == '.') {
            i += 1;
            // Read up to 3 digits of fractional seconds.
            var frac_buf: [3]u8 = .{ '0', '0', '0' };
            var frac_n: usize = 0;
            while (i < s.len and frac_n < 3 and s[i] >= '0' and s[i] <= '9') : ({
                frac_n += 1;
                i += 1;
            }) {
                frac_buf[frac_n] = s[i];
            }
            millisecond = parseU16(frac_buf[0..3]) orelse return null;
        }
    }
    // Optional trailing 'Z' (UTC) — we treat all parsed dates as UTC anyway.
    if (i < s.len and s[i] == 'Z') i += 1;
    // Skip trailing whitespace if any.
    while (i < s.len and s[i] == ' ') i += 1;
    if (i != s.len) return null;

    if (month < 1 or month > 12) return null;
    if (day < 1 or day > 31) return null;
    if (hour > 23 or minute > 59 or second > 59) return null;

    return timestampFromParts(year, @intCast(month - 1), @intCast(day), hour, minute, second, millisecond);
}

// --- internals ---

fn parseIntNS(s: []const u8, i: *usize, max_digits: usize) ?i64 {
    if (i.* >= s.len) return null;
    var neg = false;
    if (s[i.*] == '-') {
        neg = true;
        i.* += 1;
    } else if (s[i.*] == '+') {
        i.* += 1;
    }
    var value: i64 = 0;
    var n: usize = 0;
    while (i.* < s.len and n < max_digits and s[i.*] >= '0' and s[i.*] <= '9') : (n += 1) {
        value = value * 10 + (@as(i64, s[i.*]) - '0');
        i.* += 1;
    }
    if (n == 0) return null;
    return if (neg) -value else value;
}

fn parseU8(s: []const u8) ?u8 {
    if (s.len == 0) return null;
    var value: u32 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return null;
        value = value * 10 + (@as(u32, c) - '0');
    }
    if (value > 255) return null;
    return @intCast(value);
}

fn parseU16(s: []const u8) ?u16 {
    if (s.len == 0) return null;
    var value: u32 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return null;
        value = value * 10 + (@as(u32, c) - '0');
    }
    if (value > 65535) return null;
    return @intCast(value);
}

const CivilDate = struct {
    year: i32,
    month: u8, // 1-12
    day: u8, // 1-31
};

/// Howard Hinnant's `civil_from_days` (z = days since 1970-01-01).
fn civilFromDays(z: i64) CivilDate {
    // Shift epoch from 1970-01-01 to 0000-03-01.
    const z2 = z + 719468;
    const era = @divFloor(z2, 146097);
    const doe = z2 - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i64 = yoe + era * 400;
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d: i64 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m_raw: i64 = if (mp < 10) mp + 3 else mp - 9;
    const y_final: i64 = if (m_raw <= 2) y + 1 else y;
    return .{
        .year = @intCast(y_final),
        .month = @intCast(m_raw),
        .day = @intCast(d),
    };
}

/// Howard Hinnant's `days_from_civil`. `m` is 1-based (1=Jan, 12=Dec).
fn daysFromCivil(y: i64, m: u8, d: u8) i64 {
    const y_adj: i64 = if (m <= 2) y - 1 else y;
    const era: i64 = @divFloor(y_adj, 400);
    const yoe: i64 = y_adj - era * 400;
    const m_adj: u8 = if (m <= 2) m + 9 else m - 3;
    const doy: i64 = @divFloor(153 * @as(i64, m_adj) + 2, 5) + @as(i64, d) - 1;
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

test "partsFromTimestamp - epoch" {
    const p = partsFromTimestamp(0);
    try std.testing.expectEqual(@as(i32, 1970), p.year);
    try std.testing.expectEqual(@as(u8, 0), p.month);
    try std.testing.expectEqual(@as(u8, 1), p.day);
    try std.testing.expectEqual(@as(u8, 0), p.hour);
    try std.testing.expectEqual(@as(u8, 0), p.minute);
    try std.testing.expectEqual(@as(u8, 0), p.second);
    try std.testing.expectEqual(@as(u8, 4), p.weekday); // Thursday
}

test "partsFromTimestamp - known date" {
    // 2024-01-15T09:50:00.000Z = 1705312200000
    const p = partsFromTimestamp(1705312200000);
    try std.testing.expectEqual(@as(i32, 2024), p.year);
    try std.testing.expectEqual(@as(u8, 0), p.month);
    try std.testing.expectEqual(@as(u8, 15), p.day);
    try std.testing.expectEqual(@as(u8, 9), p.hour);
    try std.testing.expectEqual(@as(u8, 50), p.minute);
    try std.testing.expectEqual(@as(u8, 0), p.second);
    try std.testing.expectEqual(@as(u8, 1), p.weekday); // Monday
}

test "parseIsoDate - date only" {
    const ts = parseIsoDate("2024-01-15").?;
    try std.testing.expectEqual(@as(i64, 1705276800000), ts); // 2024-01-15T00:00:00Z
}

test "parseIsoDate - full" {
    const ts = parseIsoDate("2024-01-15T09:50:00Z").?;
    try std.testing.expectEqual(@as(i64, 1705312200000), ts);
}

test "parseIsoDate - fractional seconds" {
    const ts = parseIsoDate("2024-01-15T10:30:00.500Z").?;
    try std.testing.expectEqual(@as(i64, 1705314600500), ts);
}

test "timestampFromParts roundtrip" {
    const ts = timestampFromParts(2024, 0, 15, 10, 30, 0, 0);
    const p = partsFromTimestamp(ts);
    try std.testing.expectEqual(@as(i32, 2024), p.year);
    try std.testing.expectEqual(@as(u8, 0), p.month);
    try std.testing.expectEqual(@as(u8, 15), p.day);
}

test "two-digit year extension" {
    // Year 50 → 1950 (JS legacy)
    const ts = timestampFromParts(50, 0, 1, 0, 0, 0, 0);
    const p = partsFromTimestamp(ts);
    try std.testing.expectEqual(@as(i32, 1950), p.year);
}

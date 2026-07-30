const std = @import("std");
const Types = @import("../../types/types.zig");

/// `Intl()` constructor — creates a namespace js_object with `@@type="Intl"`.
/// The object itself has no data; it serves as the carrier for the
/// `NumberFormat` and `DateTimeFormat` methods registered on INTL_OBJECT.
pub fn IntlConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = args;
    const obj = Types.ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    obj.properties.put("@@type", .{ .string = "Intl" }) catch {};
    return .{ .value = .{ .js_object = obj } };
}

/// Helper: detect if args[0] is the Intl namespace object (method call) vs a real arg (new).
fn isMethodCall(args: []Types.Value) bool {
    if (args.len == 0) return false;
    if (args[0] != .js_object) return false;
    const type_val = args[0].js_object.properties.get("@@type") orelse return false;
    return type_val == .string and std.mem.eql(u8, type_val.string, "Intl");
}

/// Helper: coerce argument at `idx` to a string, defaulting to `"en-US"`.
fn localeFrom(args: []Types.Value, idx: usize) []const u8 {
    if (idx < args.len and args[idx] == .string) return args[idx].string;
    return "en-US";
}

/// Helper: coerce a Value to f64.
fn toF64(v: Types.Value) f64 {
    return switch (v) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => std.math.nan(f64),
    };
}

/// Locale separators table.
const LocaleSeparators = struct {
    thousands: u8,
    decimal: u8,
};

fn separatorsFor(locale: []const u8) LocaleSeparators {
    if (std.mem.eql(u8, locale, "de-DE") or std.mem.startsWith(u8, locale, "de")) {
        return .{ .thousands = '.', .decimal = ',' };
    }
    // en-US, es-MX, ja-JP, and all others default to en-US style
    return .{ .thousands = ',', .decimal = '.' };
}

/// Helper: format a number with locale-aware thousands/decimal separators.
fn formatNumberLocale(allocator: std.mem.Allocator, n: f64, locale: []const u8) ![]const u8 {
    const is_neg = n < 0;
    const abs_n = @abs(n);
    const whole: i64 = @intFromFloat(@floor(abs_n));
    const frac = abs_n - @floor(abs_n);
    const sep = separatorsFor(locale);

    // Whole part string
    const whole_str = try std.fmt.allocPrint(allocator, "{d}", .{whole});
    defer allocator.free(whole_str);

    // Build separated whole part into a fixed buffer
    var buf: [256]u8 = undefined;
    var buf_idx: usize = 0;

    const len = whole_str.len;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (i > 0 and (len - i) % 3 == 0) {
            buf[buf_idx] = sep.thousands;
            buf_idx += 1;
        }
        buf[buf_idx] = whole_str[i];
        buf_idx += 1;
    }

    // Fractional part (2 decimals)
    const frac_val: u32 = @intFromFloat(@round(frac * 100));
    if (frac_val == 0) {
        if (is_neg) {
            return try std.fmt.allocPrint(allocator, "-{s}", .{buf[0..buf_idx]});
        } else {
            return try allocator.dupe(u8, buf[0..buf_idx]);
        }
    }

    if (is_neg) {
        return try std.fmt.allocPrint(allocator, "-{s}{c}{d:0>2}", .{ buf[0..buf_idx], sep.decimal, frac_val });
    } else {
        return try std.fmt.allocPrint(allocator, "{s}{c}{d:0>2}", .{ buf[0..buf_idx], sep.decimal, frac_val });
    }
}

/// `Intl.prototype.NumberFormat(locale)` — called as method on Intl object, or via `new`.
/// Returns a `NumberFormat` js_object tagged with `@@type="NumberFormat"`.
pub fn IntlNumberFormat(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const locale = if (isMethodCall(args)) localeFrom(args, 1) else localeFrom(args, 0);
    const obj = Types.ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    obj.properties.put("@@type", .{ .string = "NumberFormat" }) catch {};

    const locale_owned = env.allocator.dupe(u8, locale) catch "en-US";
    env.owned_strings.append(env.allocator, locale_owned) catch {};
    obj.properties.put("locale", .{ .string = locale_owned }) catch {};
    return .{ .value = .{ .js_object = obj } };
}

/// `NumberFormat.prototype.format(number)` — formats a number according to locale.
pub fn NumberFormatFormat(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .js_object) return .{ .value = .{ .void = {} } };
    const num = if (args.len >= 2) toF64(args[1]) else std.math.nan(f64);
    if (std.math.isNan(num)) return .{ .value = .{ .string = "NaN" } };

    var locale: []const u8 = "en-US";
    if (args[0].js_object.properties.get("locale")) |lv| {
        if (lv == .string) locale = lv.string;
    }

    const formatted = formatNumberLocale(env.allocator, num, locale) catch return .{ .value = .{ .void = {} } };
    env.owned_strings.append(env.allocator, formatted) catch {};
    return .{ .value = .{ .string = formatted } };
}

/// `Intl.prototype.DateTimeFormat(locale)` — called as method on Intl object, or via `new`.
/// Returns a `DateTimeFormat` js_object tagged with `@@type="DateTimeFormat"`.
pub fn IntlDateTimeFormat(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const locale = if (isMethodCall(args)) localeFrom(args, 1) else localeFrom(args, 0);
    const obj = Types.ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    obj.properties.put("@@type", .{ .string = "DateTimeFormat" }) catch {};

    const locale_owned = env.allocator.dupe(u8, locale) catch "en-US";
    env.owned_strings.append(env.allocator, locale_owned) catch {};
    obj.properties.put("locale", .{ .string = locale_owned }) catch {};
    return .{ .value = .{ .js_object = obj } };
}

/// `DateTimeFormat.prototype.format(date)` — formats a Date object.
/// Expects `date` to be a js_object with `@@type="Date"` and `timestamp_ms`.
/// Minimal implementation: outputs `M/D/YYYY` matching Node's default
/// `DateTimeFormat("en-US")` short-date format.
pub fn DateTimeFormatFormat(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .js_object) return .{ .value = .{ .void = {} } };

    const date_val: Types.Value = if (args.len >= 2) args[1] else .{ .void = {} };
    const ts: f64 = switch (date_val) {
        .js_object => |o| blk: {
            if (o.properties.get("timestamp_ms")) |tsv| {
                break :blk switch (tsv) {
                    .float => |f| f,
                    .integer => |i| @as(f64, @floatFromInt(i)),
                    else => std.math.nan(f64),
                };
            }
            break :blk std.math.nan(f64);
        },
        else => std.math.nan(f64),
    };

    if (std.math.isNan(ts)) return .{ .value = .{ .string = "Invalid Date" } };

    const ms: i64 = @intFromFloat(ts);
    const sec = @divFloor(ms, 1000);
    var epoch_day: i64 = @divFloor(sec, 86400);
    var secs_of_day = sec - epoch_day * 86400;
    if (secs_of_day < 0) {
        epoch_day -= 1;
        secs_of_day += 86400;
    }

    // Leap-year-aware conversion from epoch days to YYYY-MM-DD.
    const isLeapYear = struct {
        fn check(y: i64) bool {
            return (@rem(y, 4) == 0 and @rem(y, 100) != 0) or (@rem(y, 400) == 0);
        }
    }.check;

    var year: i64 = 1970;
    while (true) {
        const days_in_year: i64 = if (isLeapYear(year)) 366 else 365;
        if (epoch_day < days_in_year) break;
        epoch_day -= days_in_year;
        year += 1;
    }

    const dim = [_]u8{ 31, if (isLeapYear(year)) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var month: u8 = 0;
    while (month < 12) : (month += 1) {
        if (epoch_day < dim[month]) break;
        epoch_day -= dim[month];
    }
    const day: i64 = epoch_day + 1;

    // Node default DateTimeFormat("en-US") short date: M/D/YYYY
    const formatted = std.fmt.allocPrint(env.allocator, "{d}/{d}/{d}", .{ month + 1, day, year }) catch return .{ .value = .{ .void = {} } };
    env.owned_strings.append(env.allocator, formatted) catch {};
    return .{ .value = .{ .string = formatted } };
}

// === Builtin object registrations ===

pub const INTL_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "NumberFormat", .func = IntlNumberFormat },
    .{ .name = "DateTimeFormat", .func = IntlDateTimeFormat },
    .{ .name = "Collator", .func = IntlCollator },
};

pub const INTL_OBJECT = Types.BuiltinObjectImpl{
    .name = "Intl",
    .methods = &INTL_METHODS,
    .properties = &.{},
};

pub const NUMBERFORMAT_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "format", .func = NumberFormatFormat },
};

pub const NUMBERFORMAT_OBJECT = Types.BuiltinObjectImpl{
    .name = "NumberFormat",
    .methods = &NUMBERFORMAT_METHODS,
    .properties = &.{},
};

pub const DATETIMEFORMAT_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "format", .func = DateTimeFormatFormat },
};

pub const DATETIMEFORMAT_OBJECT = Types.BuiltinObjectImpl{
    .name = "DateTimeFormat",
    .methods = &DATETIMEFORMAT_METHODS,
    .properties = &.{},
};

/// `Intl.prototype.Collator(locale, options)` — called as method on Intl object, or via `new`.
/// Returns a `Collator` js_object tagged with `@@type="Collator"`.
/// Options: `sensitivity` ("base" | "accent" | "case" | "variant").
pub fn IntlCollator(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const locale = if (isMethodCall(args)) localeFrom(args, 1) else localeFrom(args, 0);
    const obj = Types.ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    obj.properties.put("@@type", .{ .string = "Collator" }) catch {};

    const locale_owned = env.allocator.dupe(u8, locale) catch "en-US";
    env.owned_strings.append(env.allocator, locale_owned) catch {};
    obj.properties.put("locale", .{ .string = locale_owned }) catch {};

    // Parse options object if present
    var sensitivity: []const u8 = "variant";
    const opts_idx: usize = if (isMethodCall(args)) @as(usize, 2) else @as(usize, 1);
    if (opts_idx < args.len and args[opts_idx] == .js_object) {
        if (args[opts_idx].js_object.properties.get("sensitivity")) |sv| {
            if (sv == .string) sensitivity = sv.string;
        }
    }
    const sens_owned = env.allocator.dupe(u8, sensitivity) catch "variant";
    env.owned_strings.append(env.allocator, sens_owned) catch {};
    obj.properties.put("sensitivity", .{ .string = sens_owned }) catch {};

    return .{ .value = .{ .js_object = obj } };
}

/// `Collator.prototype.compare(a, b)` — compares two strings according to locale and sensitivity.
/// Returns -1 if a < b, 0 if equal, 1 if a > b.
pub fn CollatorCompare(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .js_object) return .{ .value = .{ .void = {} } };

    const a = if (args.len >= 2) switch (args[1]) {
        .string => |s| s,
        else => return .{ .value = .{ .integer = 0 } },
    } else "";
    const b = if (args.len >= 3) switch (args[2]) {
        .string => |s| s,
        else => return .{ .value = .{ .integer = 0 } },
    } else "";

    const sensitivity = args[0].js_object.properties.get("sensitivity");
    const sens = if (sensitivity) |s| (if (s == .string) s.string else "variant") else "variant";

    var cmp: i64 = 0;
    if (std.mem.eql(u8, sens, "base")) {
        // Base comparison: case-insensitive
        const a_lower = std.ascii.allocLowerString(env.allocator, a) catch return .{ .value = .{ .void = {} } };
        defer env.allocator.free(a_lower);
        const b_lower = std.ascii.allocLowerString(env.allocator, b) catch return .{ .value = .{ .void = {} } };
        defer env.allocator.free(b_lower);
        cmp = switch (std.mem.order(u8, a_lower, b_lower)) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
    } else {
        // Default "variant" (and "case"/"accent") — exact byte comparison
        cmp = switch (std.mem.order(u8, a, b)) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
    }

    return .{ .value = .{ .integer = cmp } };
}

pub const COLLATOR_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "compare", .func = CollatorCompare },
};

pub const COLLATOR_OBJECT = Types.BuiltinObjectImpl{
    .name = "Collator",
    .methods = &COLLATOR_METHODS,
    .properties = &.{},
};

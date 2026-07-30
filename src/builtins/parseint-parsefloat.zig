const std = @import("std");
const Types = @import("../types/types.zig");

/// Leading whitespace characters per ES String.prototype.trim: spaces, tabs,
/// line terminators (LF, CR, LS, PS) and vertical tab / form feed.
fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '\x0b' or c == '\x0c';
}

/// Trim ASCII whitespace from the start of a slice.
fn skipWhitespace(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (!isWhitespace(s[i])) break;
    }
    return s[i..];
}

/// Coerce a Value to a string slice (per ES ToString). For primitives we
/// return either an existing borrowed slice (.string) or a small static
/// literal; for numbers we allocate a heap copy tracked via
/// env.owned_strings so its lifetime matches the program.
fn coerceToString(val: Types.Value, env: *Types.Environment) []const u8 {
    return switch (val) {
        .string => |s| s,
        .void => "undefined",
        .null => "null",
        .boolean => |b| if (b) "true" else "false",
        .integer => |i| blk: {
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
            const dup = env.allocator.dupe(u8, slice) catch break :blk "0";
            env.owned_strings.append(env.allocator, dup) catch {};
            break :blk dup;
        },
        .float => |f| blk: {
            // NaN/Inf go to dedicated strings (ToString(NaN) === "NaN").
            if (std.math.isNan(f)) break :blk "NaN";
            if (std.math.isInf(f)) break :blk if (f > 0) "Infinity" else "-Infinity";
            if (f == 0.0) break :blk "0";
            var buf: [64]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{f}) catch "0";
            const dup = env.allocator.dupe(u8, slice) catch break :blk "0";
            env.owned_strings.append(env.allocator, dup) catch {};
            break :blk dup;
        },
        else => "undefined",
    };
}

/// Decode a single character as an integer digit in the given radix.
/// Returns the digit value, or null if the character isn't valid
/// (case-insensitive for letters beyond '9').
fn digitValue(c: u8, radix: u32) ?u32 {
    const v: u32 = switch (c) {
        '0'...'9' => c - '0',
        'a'...'z' => c - 'a' + 10,
        'A'...'Z' => c - 'A' + 10,
        else => return null,
    };
    if (v < radix) return v;
    return null;
}

/// Convert a value to a "radix" i32 for parseInt's second parameter.
/// Follows ES ToInt32 with safe-clamping for out-of-range floats.
fn coerceToRadix(val: Types.Value) i32 {
    return switch (val) {
        .void => 0, // undefined → 0 (auto-detect)
        .null => 0,
        .boolean => |b| if (b) 1 else 0,
        .integer => |i| std.math.cast(i32, i) orelse std.math.maxInt(i32),
        .float => |f| blk: {
            if (std.math.isNan(f)) break :blk 0;
            if (std.math.isInf(f)) break :blk if (f > 0) std.math.maxInt(i32) else std.math.minInt(i32);
            // Clamp: floats outside int range would UB @intFromFloat.
            if (f >= 2147483648.0) break :blk std.math.maxInt(i32);
            if (f <= -2147483649.0) break :blk std.math.minInt(i32);
            break :blk @intFromFloat(f);
        },
        else => 0,
    };
}

/// parseInt(string, radix?) — parses a string to an integer in the given radix.
/// Implements ES 21.1.3 with the following radix semantics:
///   - undefined / 0 → auto-detect (only "0x"/"0X" → 16, else 10)
///   - explicit 16 → also accept and strip "0x" prefix
///   - [2, 36] → use that radix
///   - everything else (incl. < 2, > 36, ambiguous) → NaN
/// Trims leading whitespace, accepts optional +/- sign, parses the longest
/// leading digit run; returns NaN if no digits were consumed. Integers that
/// would overflow i64 are clamped to i64.maxInt — a documented divergence
/// from V8 (whose floats represent arbitrary-precision results past 2^53).
pub fn parseInt(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const s = if (args.len == 0) "" else skipWhitespace(coerceToString(args[0], env));
    var radix: i32 = if (args.len >= 2) coerceToRadix(args[1]) else 0;

    var idx: usize = 0;
    const is_negative: bool = blk: {
        if (idx < s.len and s[idx] == '-') {
            idx += 1;
            break :blk true;
        }
        if (idx < s.len and s[idx] == '+') {
            idx += 1;
        }
        break :blk false;
    };

    if (radix == 0) {
        // Auto-detect: only "0x"/"0X" triggers base 16 (V8 behavior).
        // The ES2015+ "0o"/"0b" prefixes are NOT auto-detected by parseInt
        // — Number literal syntax accepts them, but parseInt always parses
        // them in base 10 (the "o"/"b" stops digit parsing).
        if (idx + 1 < s.len and s[idx] == '0' and (s[idx + 1] == 'x' or s[idx + 1] == 'X')) {
            radix = 16;
            idx += 2;
        } else {
            radix = 10;
        }
    } else if (radix == 16) {
        // Explicit radix 16: also strip an "0x"/"0X" prefix if present.
        if (idx + 1 < s.len and s[idx] == '0' and (s[idx + 1] == 'x' or s[idx + 1] == 'X')) {
            idx += 2;
        }
    }

    if (radix < 2 or radix > 36) {
        return .{ .value = .{ .float = std.math.nan(f64) } };
    }

    const base: u32 = @intCast(radix);
    var parsed: u64 = 0;
    var any_digits = false;
    var overflow = false;

    // `std.math.maxInt` returns comptime_int, so anchor it as u64 to force
    // u64 arithmetic in the per-digit overflow check (avoiding coercion
    // to the narrower u32 type of `dv` / `base`).
    const max_u64: u64 = std.math.maxInt(u64);
    while (idx < s.len) {
        const dv = digitValue(s[idx], base) orelse break;
        // Saturating multiply: detect u64 overflow before the multiply
        // to avoid UB; once overflowed, keep consuming digits but stop
        // updating the running value.
        const threshold: u64 = (max_u64 - dv) / base;
        if (parsed > threshold) {
            overflow = true;
            idx += 1;
            continue;
        }
        parsed = parsed * base + dv;
        any_digits = true;
        idx += 1;
    }

    if (!any_digits) {
        return .{ .value = .{ .float = std.math.nan(f64) } };
    }

    const saturated: u64 = if (overflow) std.math.maxInt(i64) else parsed;
    const signed: i64 = @intCast(saturated);
    const signed_parsed: i64 = if (is_negative) -signed else signed;

    return .{ .value = .{ .integer = signed_parsed } };
}

/// parseFloat(string) — parses a string to a Number (f64).
/// Trims leading whitespace, accepts optional +/- sign, recognizes the
/// case-sensitive literal "Infinity" (V8 behavior — "infinity"/"INFINITY"
/// return NaN), and parses the longest leading numeric prefix using
/// std.fmt.parseFloat (walking back one character at a time on failure
/// until a parse succeeds or the remainder is empty).
pub fn parseFloat(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const s = if (args.len == 0) "" else skipWhitespace(coerceToString(args[0], env));
    var idx: usize = 0;

    const is_negative: bool = blk: {
        if (idx < s.len and s[idx] == '-') {
            idx += 1;
            break :blk true;
        }
        if (idx < s.len and s[idx] == '+') {
            idx += 1;
        }
        break :blk false;
    };

    if (idx >= s.len) {
        return .{ .value = .{ .float = std.math.nan(f64) } };
    }

    // Case-sensitive exact "Infinity" — only the literal capital-I form
    // is recognized (V8 returns NaN for "infinity" / "INFINITY").
    if (idx + 8 <= s.len and std.mem.eql(u8, s[idx..][0..8], "Infinity")) {
        const inf = std.math.inf(f64);
        return .{ .value = .{ .float = if (is_negative) -inf else inf } };
    }

    // V8's parseFloat only accepts strings whose first char (after the
    // optional sign, already stripped above) is a digit or '.'. Zig's
    // std.fmt.parseFloat is more lenient (it handles "infinity"/"inf"
    // case-insensitively), so we must reject leading alphabetic input
    // here to avoid mismatch with V8.
    const first = s[idx];
    if (!std.ascii.isDigit(first) and first != '.') {
        return .{ .value = .{ .float = std.math.nan(f64) } };
    }

    // Longest-prefix parse: try the full remainder, then trim trailing
    // chars one at a time until something parses or we run out.
    var remaining = s[idx..];
    while (remaining.len > 0) {
        if (std.fmt.parseFloat(f64, remaining)) |v| {
            const result = if (is_negative) -v else v;
            return .{ .value = .{ .float = result } };
        } else |_| {
            if (remaining.len == 1) return .{ .value = .{ .float = std.math.nan(f64) } };
            remaining = remaining[0 .. remaining.len - 1];
        }
    }

    return .{ .value = .{ .float = std.math.nan(f64) } };
}

// === Unit tests ===
//
// Unit tests use the `var args = [_]Types.Value{...}; ... fn(&args, &env)`
// pattern from error.zig — required because `&[_]Types.Value{...}` produces
// `*const [N]T` which cannot coerce to `[]T` (mutable slice) without a
// typed intermediate.

test "parseInt: decimal integer basics" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    var a_args = [_]Types.Value{.{ .string = "42" }};
    try std.testing.expectEqual(@as(i64, 42), parseInt(&a_args, &env).value.integer);

    var b_args = [_]Types.Value{.{ .string = "-42" }};
    try std.testing.expectEqual(@as(i64, -42), parseInt(&b_args, &env).value.integer);

    var c_args = [_]Types.Value{ .{ .string = "+42" }, .{ .integer = 10 } };
    try std.testing.expectEqual(@as(i64, 42), parseInt(&c_args, &env).value.integer);
}

test "parseInt: leading whitespace and trailing junk" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    var a_args = [_]Types.Value{.{ .string = "  42  " }};
    try std.testing.expectEqual(@as(i64, 42), parseInt(&a_args, &env).value.integer);

    var b_args = [_]Types.Value{.{ .string = "42px" }};
    try std.testing.expectEqual(@as(i64, 42), parseInt(&b_args, &env).value.integer);
}

test "parseInt: explicit radix" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    var a_args = [_]Types.Value{ .{ .string = "FF" }, .{ .integer = 16 } };
    try std.testing.expectEqual(@as(i64, 255), parseInt(&a_args, &env).value.integer);

    var b_args = [_]Types.Value{ .{ .string = "1010" }, .{ .integer = 2 } };
    try std.testing.expectEqual(@as(i64, 10), parseInt(&b_args, &env).value.integer);

    var c_args = [_]Types.Value{ .{ .string = "zz" }, .{ .integer = 36 } };
    try std.testing.expectEqual(@as(i64, 1295), parseInt(&c_args, &env).value.integer);
}

test "parseInt: 0x hex prefix auto-detect" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    var a_args = [_]Types.Value{.{ .string = "0xFF" }};
    try std.testing.expectEqual(@as(i64, 255), parseInt(&a_args, &env).value.integer);

    var b_args = [_]Types.Value{.{ .string = "0X10" }};
    try std.testing.expectEqual(@as(i64, 16), parseInt(&b_args, &env).value.integer);

    var c_args = [_]Types.Value{ .{ .string = "0xFF" }, .{ .integer = 16 } };
    try std.testing.expectEqual(@as(i64, 255), parseInt(&c_args, &env).value.integer);
}

test "parseInt: 0o/0b prefixes do NOT auto-detect (V8 behavior)" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    // V8: parseInt("0o77") → 0. Number literal syntax accepts 0o77 but
    // parseInt always parses in base 10 once "o" is not a base-10 digit.
    var a_args = [_]Types.Value{.{ .string = "0o77" }};
    try std.testing.expectEqual(@as(i64, 0), parseInt(&a_args, &env).value.integer);

    var b_args = [_]Types.Value{.{ .string = "0b1010" }};
    try std.testing.expectEqual(@as(i64, 0), parseInt(&b_args, &env).value.integer);
}

test "parseInt: NaN cases" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    const nan_cases = [_][]const u8{
        "",      // empty string
        "abc",   // no leading digits
        " ",     // whitespace only
        "0xZZZ", // hex but Z exceeds base 16
    };
    for (nan_cases) |c| {
        var args = [_]Types.Value{.{ .string = c }};
        const r = parseInt(&args, &env);
        try std.testing.expect(r.value == .float);
        try std.testing.expect(std.math.isNan(r.value.float));
    }

    // Out-of-range radix → NaN.
    var r1 = [_]Types.Value{ .{ .string = "10" }, .{ .integer = 1 } };
    try std.testing.expect(std.math.isNan(parseInt(&r1, &env).value.float));
    var r2 = [_]Types.Value{ .{ .string = "10" }, .{ .integer = 37 } };
    try std.testing.expect(std.math.isNan(parseInt(&r2, &env).value.float));
}

test "parseInt: leading zeros stay in base 10" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    // "077" with no radix → 77 in base 10 (V8 disallows legacy octal).
    var a_args = [_]Types.Value{.{ .string = "077" }};
    try std.testing.expectEqual(@as(i64, 77), parseInt(&a_args, &env).value.integer);

    // "077" with explicit radix 8 → 63.
    var b_args = [_]Types.Value{ .{ .string = "077" }, .{ .integer = 8 } };
    try std.testing.expectEqual(@as(i64, 63), parseInt(&b_args, &env).value.integer);
}

test "parseInt: overflow clamps to i64.maxInt" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    var a_args = [_]Types.Value{.{ .string = "99999999999999999999" }};
    try std.testing.expectEqual(std.math.maxInt(i64), parseInt(&a_args, &env).value.integer);

    var b_args = [_]Types.Value{.{ .string = "-99999999999999999999" }};
    try std.testing.expectEqual(-std.math.maxInt(i64), parseInt(&b_args, &env).value.integer);
}

test "parseInt: undefined / null radix fall back to auto-detect" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    var a_args = [_]Types.Value{ .{ .string = "42" }, .{ .void = {} } };
    try std.testing.expectEqual(@as(i64, 42), parseInt(&a_args, &env).value.integer);

    var b_args = [_]Types.Value{ .{ .string = "42" }, .{ .null = {} } };
    try std.testing.expectEqual(@as(i64, 42), parseInt(&b_args, &env).value.integer);

    var c_args = [_]Types.Value{ .{ .string = "42" }, .{ .integer = 0 } };
    try std.testing.expectEqual(@as(i64, 42), parseInt(&c_args, &env).value.integer);
}

test "parseInt: non-string input coerces via ToString" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    // Boolean true → "true" → no digits → NaN.
    var a_args = [_]Types.Value{.{ .boolean = true }};
    try std.testing.expect(std.math.isNan(parseInt(&a_args, &env).value.float));

    // Integer 42 → "42" → 42.
    var b_args = [_]Types.Value{.{ .integer = 42 }};
    try std.testing.expectEqual(@as(i64, 42), parseInt(&b_args, &env).value.integer);

    // Float 3.14 → "3.14" → "3" in base 10 → 3 (parseInt truncates).
    var c_args = [_]Types.Value{.{ .float = 3.14 }};
    try std.testing.expectEqual(@as(i64, 3), parseInt(&c_args, &env).value.integer);
}

test "parseFloat: integer and decimal basics" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    var a_args = [_]Types.Value{.{ .string = "3.14" }};
    try std.testing.expectEqual(@as(f64, 3.14), parseFloat(&a_args, &env).value.float);

    var b_args = [_]Types.Value{.{ .string = "  3.14  " }};
    try std.testing.expectEqual(@as(f64, 3.14), parseFloat(&b_args, &env).value.float);
}

test "parseFloat: trailing junk and sign" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    var a_args = [_]Types.Value{.{ .string = "3.14abc" }};
    try std.testing.expectEqual(@as(f64, 3.14), parseFloat(&a_args, &env).value.float);

    var b_args = [_]Types.Value{.{ .string = "-3.14" }};
    try std.testing.expectEqual(@as(f64, -3.14), parseFloat(&b_args, &env).value.float);

    var c_args = [_]Types.Value{.{ .string = "+3.14" }};
    try std.testing.expectEqual(@as(f64, 3.14), parseFloat(&c_args, &env).value.float);
}

test "parseFloat: scientific notation and leading dot" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    var a_args = [_]Types.Value{.{ .string = "3.14e2" }};
    try std.testing.expectEqual(@as(f64, 314.0), parseFloat(&a_args, &env).value.float);

    var b_args = [_]Types.Value{.{ .string = ".5" }};
    try std.testing.expectEqual(@as(f64, 0.5), parseFloat(&b_args, &env).value.float);
}

test "parseFloat: exact case-sensitive Infinity" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    // Only the literal capital-I form matches.
    var a_args = [_]Types.Value{.{ .string = "Infinity" }};
    try std.testing.expectEqual(std.math.inf(f64), parseFloat(&a_args, &env).value.float);

    var b_args = [_]Types.Value{.{ .string = "+Infinity" }};
    try std.testing.expectEqual(std.math.inf(f64), parseFloat(&b_args, &env).value.float);

    var c_args = [_]Types.Value{.{ .string = "-Infinity" }};
    const c_val = parseFloat(&c_args, &env).value.float;
    try std.testing.expect(std.math.isInf(c_val));
    try std.testing.expect(c_val < 0.0);

    // Other casings return NaN (V8 differentiation).
    var d_args = [_]Types.Value{.{ .string = "infinity" }};
    try std.testing.expect(std.math.isNan(parseFloat(&d_args, &env).value.float));

    var e_args = [_]Types.Value{.{ .string = "INFINITY" }};
    try std.testing.expect(std.math.isNan(parseFloat(&e_args, &env).value.float));

    // "Inf" alone must not match — only the full literal.
    var f_args = [_]Types.Value{.{ .string = "Inf" }};
    try std.testing.expect(std.math.isNan(parseFloat(&f_args, &env).value.float));
}

test "parseFloat: NaN cases" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    const nan_cases = [_][]const u8{ "", " ", "abc", "+" };
    for (nan_cases) |c| {
        var args = [_]Types.Value{.{ .string = c }};
        try std.testing.expect(std.math.isNan(parseFloat(&args, &env).value.float));
    }
}

test "parseFloat: non-string input coerces via ToString" {
    const allocator = std.testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    // Integer 42 → "42" → 42.0.
    var a_args = [_]Types.Value{.{ .integer = 42 }};
    try std.testing.expectEqual(@as(f64, 42.0), parseFloat(&a_args, &env).value.float);

    // Boolean true → "true" → NaN (no leading digits).
    var b_args = [_]Types.Value{.{ .boolean = true }};
    try std.testing.expect(std.math.isNan(parseFloat(&b_args, &env).value.float));
}

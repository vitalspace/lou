//! JS-compatible `Number` -> `String` conversion.
//!
//! ECMA-262 uses the shortest round-trip digits plus fixed rules for when to
//! switch to exponential notation (`1e+21`, `2e-7`), which is not what a plain
//! `{d}` format does.

const std = @import("std");

/// Append `f` to `buf` the way `String(f)` would.
pub fn appendFloat(a: std.mem.Allocator, buf: *std.ArrayList(u8), f: f64) void {
    if (std.math.isNan(f)) {
        buf.appendSlice(a, "NaN") catch {};
        return;
    }
    if (std.math.isInf(f)) {
        buf.appendSlice(a, if (f < 0) "-Infinity" else "Infinity") catch {};
        return;
    }
    if (f == 0) {
        if (std.math.signbit(f)) buf.append(a, '-') catch {};
        buf.append(a, '0') catch {};
        return;
    }
    var tmp: [64]u8 = undefined;
    const sci = std.fmt.bufPrint(&tmp, "{e}", .{f}) catch {
        return;
    };
    appendFromSci(a, buf, sci);
}

/// Rewrite Zig's shortest scientific form (`-1.2345e20`) into the form JS uses.
fn appendFromSci(a: std.mem.Allocator, buf: *std.ArrayList(u8), sci: []const u8) void {
    var i: usize = 0;
    if (i < sci.len and sci[i] == '-') {
        buf.append(a, '-') catch {};
        i += 1;
    }
    // Collect the significant digits (mantissa without the decimal point).
    var digits: [32]u8 = undefined;
    var k: usize = 0;
    while (i < sci.len and sci[i] != 'e' and sci[i] != 'E') : (i += 1) {
        if (sci[i] == '.') continue;
        if (k < digits.len) {
            digits[k] = sci[i];
            k += 1;
        }
    }
    // Trim insignificant trailing zeros ("10" stays as is, "1.50" is not emitted
    // by Zig, but be safe).
    while (k > 1 and digits[k - 1] == '0') k -= 1;

    var exp: i32 = 0;
    if (i < sci.len) {
        i += 1; // 'e'
        var negative = false;
        if (i < sci.len and (sci[i] == '+' or sci[i] == '-')) {
            negative = sci[i] == '-';
            i += 1;
        }
        while (i < sci.len and sci[i] >= '0' and sci[i] <= '9') : (i += 1) {
            exp = exp * 10 + @as(i32, sci[i] - '0');
        }
        if (negative) exp = -exp;
    }
    if (k == 0) {
        buf.append(a, '0') catch {};
        return;
    }
    const n: i32 = exp + 1; // decimal point position relative to the first digit

    if (k <= @as(usize, @intCast(@max(n, 0))) and n <= 21) {
        // Plain integer: digits followed by zeros.
        buf.appendSlice(a, digits[0..k]) catch {};
        var pad: i32 = n - @as(i32, @intCast(k));
        while (pad > 0) : (pad -= 1) buf.append(a, '0') catch {};
        return;
    }
    if (0 < n and n <= 21) {
        const cut: usize = @intCast(n);
        buf.appendSlice(a, digits[0..cut]) catch {};
        buf.append(a, '.') catch {};
        buf.appendSlice(a, digits[cut..k]) catch {};
        return;
    }
    if (-6 < n and n <= 0) {
        buf.appendSlice(a, "0.") catch {};
        var pad: i32 = -n;
        while (pad > 0) : (pad -= 1) buf.append(a, '0') catch {};
        buf.appendSlice(a, digits[0..k]) catch {};
        return;
    }
    // Exponential notation with an explicit sign, like `1e+21` / `2e-7`.
    buf.append(a, digits[0]) catch {};
    if (k > 1) {
        buf.append(a, '.') catch {};
        buf.appendSlice(a, digits[1..k]) catch {};
    }
    buf.append(a, 'e') catch {};
    const e10 = n - 1;
    buf.append(a, if (e10 < 0) '-' else '+') catch {};
    var mag: u32 = @intCast(if (e10 < 0) -e10 else e10);
    var num: [12]u8 = undefined;
    const text = std.fmt.bufPrint(&num, "{d}", .{mag}) catch "0";
    _ = &mag;
    buf.appendSlice(a, text) catch {};
}

/// Convenience: return an owned string for `f`.
pub fn allocFloat(a: std.mem.Allocator, f: f64) ![]u8 {
    var buf = std.ArrayList(u8).initCapacity(a, 24) catch return error.OutOfMemory;
    appendFloat(a, &buf, f);
    return buf.toOwnedSlice(a);
}

test "float formatting matches JS" {
    const cases = [_]struct { v: f64, want: []const u8 }{
        .{ .v = 1e21, .want = "1e+21" },
        .{ .v = 2e-7, .want = "2e-7" },
        .{ .v = 0.000001, .want = "0.000001" },
        .{ .v = 1.5e3, .want = "1500" },
        .{ .v = 0.30000000000000004, .want = "0.30000000000000004" },
        .{ .v = 12345.6789, .want = "12345.6789" },
        .{ .v = 1e300, .want = "1e+300" },
        .{ .v = 0.5, .want = "0.5" },
        .{ .v = -2.5, .want = "-2.5" },
        .{ .v = 100, .want = "100" },
        .{ .v = 5e-324, .want = "5e-324" },
    };
    for (cases) |c| {
        const got = try allocFloat(std.testing.allocator, c.v);
        defer std.testing.allocator.free(got);
        try std.testing.expectEqualStrings(c.want, got);
    }
}

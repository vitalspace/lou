const std = @import("std");
const Types = @import("../types/types.zig");

/// Convert any Value to a number (f64), following ECMAScript coercion rules.
/// null → 0, undefined → NaN, boolean true→1 false→0, string trimmed→parsed,
/// integer/float as-is, BigInt via string, others → NaN.
fn toNumber(val: Types.Value, allocator: std.mem.Allocator) f64 {
    return switch (val) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        .boolean => |b| if (b) 1.0 else 0.0,
        .void => std.math.nan(f64),
        .null => 0.0,
        .string => |s| {
            const trimmed = std.mem.trim(u8, s, " \t\n\r");
            if (trimmed.len == 0) return 0.0;
            return std.fmt.parseFloat(f64, trimmed) catch std.math.nan(f64);
        },
        .big_int => |bi| {
            const s = bi.value.toString(allocator, 10, .lower) catch return std.math.nan(f64);
            defer allocator.free(s);
            return std.fmt.parseFloat(f64, s) catch std.math.nan(f64);
        },
        else => std.math.nan(f64),
    };
}

/// isFinite(value) — returns true if value coerces to a finite number.
/// Coerces the argument to number first (unlike Number.isFinite).
pub fn isFinite(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .boolean = false } };
    const num = toNumber(args[0], env.allocator);
    return .{ .value = .{ .boolean = !std.math.isNan(num) and !std.math.isInf(num) } };
}

/// isNaN(value) — returns true if value coerces to NaN.
/// Coerces the argument to number first (unlike Number.isNaN).
pub fn isNaN(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .boolean = true } };
    const num = toNumber(args[0], env.allocator);
    return .{ .value = .{ .boolean = std.math.isNan(num) } };
}

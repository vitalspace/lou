const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const isFiniteFn = @import("../isfinite-isnan.zig").isFinite;
const isNaNFn = @import("../isfinite-isnan.zig").isNaN;
const parseIntFn = @import("../parseint-parsefloat.zig").parseInt;
const parseFloatFn = @import("../parseint-parsefloat.zig").parseFloat;

// ============================================================================
// Wrapper helpers for `new Number(value)` and prototype method dispatch
// ============================================================================

/// Extract the numeric value from a Number wrapper js_object.
fn extractNumberFromWrapper(obj: *const Types.ObjectValue) ?Types.Value {
    if (obj.properties.get("@@type")) |tag| {
        if (tag != .string or !std.mem.eql(u8, tag.string, "Number")) return null;
    } else return null;
    const prim = obj.properties.get("@@primitive") orelse return null;
    if (prim != .integer and prim != .float) return null;
    return prim;
}

/// Get the numeric value as f64, from a primitive (.integer/.float) or wrapper.
fn toF64(val: Types.Value) ?f64 {
    return switch (val) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        .js_object => |obj| blk: {
            const prim = extractNumberFromWrapper(obj) orelse break :blk null;
            break :blk switch (prim) {
                .integer => |i| @floatFromInt(i),
                .float => |f| f,
                else => null,
            };
        },
        else => null,
    };
}

/// Create a Number wrapper js_object for `new Number(value)`.
pub fn makeNumberWrapper(env: *Types.Environment, v: Types.Value) !?Types.Value {
    if (v != .integer and v != .float) return null;
    const obj = try Types.ObjectValue.init(env.allocator);
    errdefer obj.deinit();
    const tag = try env.allocator.dupe(u8, "Number");
    errdefer env.allocator.free(tag);
    try env.owned_strings.append(env.allocator, tag);
    try obj.properties.put("@@type", .{ .string = tag });
    try obj.properties.put("@@primitive", v);
    try env.objects.append(env.allocator, obj);
    return Types.Value{ .js_object = obj };
}

// ============================================================================
// Static methods
// ============================================================================

/// Number.isFinite(value) — no coercion, strictly numeric check.
pub fn numberIsFinite(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .boolean = false } };
    return switch (args[0]) {
        .integer => .{ .value = .{ .boolean = true } },
        .float => |f| .{ .value = .{ .boolean = !std.math.isNan(f) and !std.math.isInf(f) } },
        else => .{ .value = .{ .boolean = false } },
    };
}

/// Number.isNaN(value) — returns true only if value is exactly NaN.
pub fn numberIsNaN(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .boolean = false } };
    return switch (args[0]) {
        .float => |f| .{ .value = .{ .boolean = std.math.isNan(f) } },
        else => .{ .value = .{ .boolean = false } },
    };
}

/// Number.isInteger(value) — true for finite integer values.
pub fn numberIsInteger(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .boolean = false } };
    return switch (args[0]) {
        .integer => .{ .value = .{ .boolean = true } },
        .float => |f| .{ .value = .{ .boolean = !std.math.isNan(f) and !std.math.isInf(f) and f == @floor(f) } },
        else => .{ .value = .{ .boolean = false } },
    };
}

/// Number.isSafeInteger(value) — integer in [-2^53+1, 2^53-1].
pub fn numberIsSafeInteger(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .boolean = false } };
    return switch (args[0]) {
        .integer => |i| .{ .value = .{ .boolean = i >= -9007199254740991 and i <= 9007199254740991 } },
        .float => |f| .{ .value = .{ .boolean = !std.math.isNan(f) and !std.math.isInf(f) and
            f >= -9007199254740991.0 and f <= 9007199254740991.0 and
            @as(f64, @floatFromInt(@as(i64, @intFromFloat(f)))) == f } },
        .big_int => |big| .{ .value = .{ .boolean = if (big.toI64()) |i|
            i >= -9007199254740991 and i <= 9007199254740991
        else
            false
        } },
        else => .{ .value = .{ .boolean = false } },
    };
}

/// Number.parseInt(string, radix?) — delegates to global parseInt.
pub fn numberParseInt(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return parseIntFn(args, env);
}

/// Number.parseFloat(string) — delegates to global parseFloat.
pub fn numberParseFloat(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return parseFloatFn(args, env);
}

// ============================================================================
// Prototype methods
// ============================================================================

/// Number.prototype.toString([radix]) — radix 2-36, default 10.
pub fn numberToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "0" } };

    const radix: u8 = if (args.len >= 2) blk: {
        break :blk switch (args[1]) {
            .integer => |i| if (i >= 2 and i <= 36) @as(u8, @intCast(i)) else 10,
            else => 10,
        };
    } else 10;

    // Handle integer primitive
    if (args[0] == .integer) {
        const i = args[0].integer;
        if (radix == 10) {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
            const result = env.allocator.dupe(u8, s) catch return .{ .value = .{ .void = {} } };
            env.owned_strings.append(env.allocator, result) catch {};
            return .{ .value = .{ .string = result } };
        }
        const is_neg = i < 0;
        const abs_val: u64 = if (is_neg) @intCast(-i) else @intCast(i);
        var buf: [64]u8 = undefined;
        var idx: usize = buf.len;
        var n = abs_val;
        if (n == 0) {
            idx -= 1;
            buf[idx] = '0';
        } else {
            while (n > 0) : (n /= radix) {
                idx -= 1;
                const d: u8 = @intCast(n % radix);
                buf[idx] = if (d < 10) '0' + d else 'a' + (d - 10);
            }
        }
        if (is_neg) {
            idx -= 1;
            buf[idx] = '-';
        }
        const s = env.allocator.dupe(u8, buf[idx..]) catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, s) catch {};
        return .{ .value = .{ .string = s } };
    }

    // Handle float/wrapper
    const num = toF64(args[0]) orelse return .{ .value = .{ .void = {} } };
    if (std.math.isNan(num)) {
        const s = env.allocator.dupe(u8, "NaN") catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, s) catch {};
        return .{ .value = .{ .string = s } };
    }
    if (std.math.isInf(num)) {
        const s = if (num > 0)
            env.allocator.dupe(u8, "Infinity") catch return .{ .value = .{ .void = {} } }
        else
            env.allocator.dupe(u8, "-Infinity") catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, s) catch {};
        return .{ .value = .{ .string = s } };
    }

    if (radix == 10) {
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{num}) catch "0";
        const result = env.allocator.dupe(u8, s) catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    return .{ .value = .{ .void = {} } };
}

/// Number.prototype.toFixed([digits]) — fixed-point notation.
pub fn numberToFixed(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "0" } };
    const num = toF64(args[0]) orelse return .{ .value = .{ .void = {} } };

    const digits: usize = if (args.len >= 2) blk: {
        break :blk switch (args[1]) {
            .integer => |i| if (i >= 0 and i <= 100) @as(usize, @intCast(i)) else @as(usize, 0),
            .float => |f| if (f >= 0 and f <= 100) @as(usize, @intFromFloat(f)) else @as(usize, 0),
            else => 0,
        };
    } else 0;

    if (std.math.isNan(num)) {
        const s = env.allocator.dupe(u8, "NaN") catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, s) catch {};
        return .{ .value = .{ .string = s } };
    }
    if (std.math.isInf(num)) {
        const s = if (num > 0)
            env.allocator.dupe(u8, "Infinity") catch return .{ .value = .{ .void = {} } }
        else
            env.allocator.dupe(u8, "-Infinity") catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, s) catch {};
        return .{ .value = .{ .string = s } };
    }

    // Format using bufPrint with precision specifier
    var buf: [512]u8 = undefined;
    const is_neg = num < 0.0;
    const abs_val = if (is_neg) -num else num;

    if (digits == 0) {
        const rounded = @round(abs_val);
        const int_val: i64 = @intFromFloat(rounded);
        const s = if (is_neg)
            std.fmt.bufPrint(&buf, "-{d}", .{int_val}) catch "0"
        else
            std.fmt.bufPrint(&buf, "{d}", .{int_val}) catch "0";
        const result = env.allocator.dupe(u8, s) catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    var multiplier: f64 = 1.0;
    var di: usize = 0;
    while (di < digits) : (di += 1) { multiplier *= 10.0; }
    const scaled = @round(abs_val * multiplier);
    const int_part_f = @floor(abs_val);
    const frac_val_f = @mod(scaled, multiplier);

    // For very large numbers beyond u64 range, fall back to toString
    if (int_part_f > @as(f64, @floatFromInt(std.math.maxInt(u64))) or int_part_f < 0) {
        return numberToString(args, env);
    }
    const int_part: u64 = @intFromFloat(int_part_f);
    const frac_val: u64 = @intFromFloat(frac_val_f);

    var out_buf: [512]u8 = undefined;
    // Format int_part.fraction with proper zero-padding (no stale-pointer shift)
    var idx: usize = 0;
    if (is_neg) {
        out_buf[idx] = '-';
        idx += 1;
    }
    const int_str = std.fmt.bufPrint(out_buf[idx..], "{d}", .{int_part}) catch "0";
    idx += int_str.len;
    if (digits > 0) {
        out_buf[idx] = '.';
        idx += 1;
        // Format fraction to a temp buffer to avoid stale-pointer issues
        var frac_buf: [32]u8 = undefined;
        const frac_str = std.fmt.bufPrint(&frac_buf, "{d}", .{frac_val}) catch "0";
        const pad = digits -| frac_str.len;
        for (0..pad) |_| {
            out_buf[idx] = '0';
            idx += 1;
        }
        @memcpy(out_buf[idx .. idx + frac_str.len], frac_str);
        idx += frac_str.len;
    }
    const s2 = out_buf[0..idx];
    const result = env.allocator.dupe(u8, s2) catch return .{ .value = .{ .void = {} } };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

/// Number.prototype.toExponential([fractionDigits]) — exponential notation.
pub fn numberToExponential(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "0e+0" } };
    const num = toF64(args[0]) orelse return .{ .value = .{ .void = {} } };

    if (std.math.isNan(num)) {
        const s = env.allocator.dupe(u8, "NaN") catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, s) catch {};
        return .{ .value = .{ .string = s } };
    }
    if (std.math.isInf(num)) {
        const s = if (num > 0)
            env.allocator.dupe(u8, "Infinity") catch return .{ .value = .{ .void = {} } }
        else
            env.allocator.dupe(u8, "-Infinity") catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, s) catch {};
        return .{ .value = .{ .string = s } };
    }

    if (num == 0.0) {
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "0e+0", .{}) catch "0e+0";
        const result = env.allocator.dupe(u8, s) catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    const is_neg = num < 0.0;
    const abs_val = if (is_neg) -num else num;
    var exp: i64 = 0;
    var mantissa = abs_val;
    if (mantissa >= 10.0) {
        while (mantissa >= 10.0) : (exp += 1) { mantissa /= 10.0; }
    } else if (mantissa < 1.0) {
        while (mantissa < 1.0) : (exp -= 1) { mantissa *= 10.0; }
    }

    var buf: [128]u8 = undefined;
    const s = if (is_neg) blk: {
        if (exp >= 0)
            break :blk std.fmt.bufPrint(&buf, "-{d}e+{d}", .{ mantissa, exp }) catch "0e+0"
        else
            break :blk std.fmt.bufPrint(&buf, "-{d}e{d}", .{ mantissa, exp }) catch "0e+0";
    } else blk: {
        if (exp >= 0)
            break :blk std.fmt.bufPrint(&buf, "{d}e+{d}", .{ mantissa, exp }) catch "0e+0"
        else
            break :blk std.fmt.bufPrint(&buf, "{d}e{d}", .{ mantissa, exp }) catch "0e+0";
    };
    const result = env.allocator.dupe(u8, s) catch return .{ .value = .{ .void = {} } };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

/// Number.prototype.toPrecision([precision]) — significant digits.
pub fn numberToPrecision(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "0" } };
    const num = toF64(args[0]) orelse return .{ .value = .{ .void = {} } };

    if (std.math.isNan(num)) {
        const s = env.allocator.dupe(u8, "NaN") catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, s) catch {};
        return .{ .value = .{ .string = s } };
    }
    if (std.math.isInf(num)) {
        const s = if (num > 0)
            env.allocator.dupe(u8, "Infinity") catch return .{ .value = .{ .void = {} } }
        else
            env.allocator.dupe(u8, "-Infinity") catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, s) catch {};
        return .{ .value = .{ .string = s } };
    }

    // Default: just call toString
    return numberToString(args, env);
}

/// Number.prototype.valueOf() — returns the primitive numeric value.
pub fn numberValueOf(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    return switch (args[0]) {
        .integer => |i| .{ .value = .{ .integer = i } },
        .float => |f| .{ .value = .{ .float = f } },
        .js_object => |obj| {
            const prim = extractNumberFromWrapper(obj) orelse return .{ .value = .{ .void = {} } };
            return .{ .value = prim };
        },
        else => .{ .value = .{ .void = {} } },
    };
}

// ============================================================================
// Static properties
// ============================================================================

pub const NUMBER_STATIC_PROPERTIES = [_]Types.BuiltinProperty{
    .{ .name = "MAX_VALUE", .value = .{ .float = 1.7976931348623157e+308 } },
    .{ .name = "MIN_VALUE", .value = .{ .float = 5e-324 } },
    .{ .name = "NaN", .value = .{ .float = std.math.nan(f64) } },
    .{ .name = "NEGATIVE_INFINITY", .value = .{ .float = -std.math.inf(f64) } },
    .{ .name = "POSITIVE_INFINITY", .value = .{ .float = std.math.inf(f64) } },
    .{ .name = "EPSILON", .value = .{ .float = 2.220446049250313e-16 } },
    .{ .name = "MAX_SAFE_INTEGER", .value = .{ .integer = 9007199254740991 } },
    .{ .name = "MIN_SAFE_INTEGER", .value = .{ .integer = -9007199254740991 } },
};

// ============================================================================
// Method registries
// ============================================================================

pub const NUMBER_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "isFinite", .func = numberIsFinite },
    .{ .name = "isNaN", .func = numberIsNaN },
    .{ .name = "isInteger", .func = numberIsInteger },
    .{ .name = "isSafeInteger", .func = numberIsSafeInteger },
    .{ .name = "parseInt", .func = numberParseInt },
    .{ .name = "parseFloat", .func = numberParseFloat },
    .{ .name = "toString", .func = numberToString },
    .{ .name = "toFixed", .func = numberToFixed },
    .{ .name = "toExponential", .func = numberToExponential },
    .{ .name = "toPrecision", .func = numberToPrecision },
    .{ .name = "valueOf", .func = numberValueOf },
};

pub const NUMBER_OBJECT = Types.BuiltinObjectImpl{
    .name = "Number",
    .methods = &NUMBER_METHODS,
    .properties = &NUMBER_STATIC_PROPERTIES,
};

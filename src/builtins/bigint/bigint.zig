const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn BigIntConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) {
        return .{ .value = .{ .void = {} } };
    }
    const arg = args[0];
    switch (arg) {
        .big_int => return .{ .value = arg },
        .integer => |i| {
            const big = Ast.BigIntValue.fromString(env.allocator, "0") catch return .{ .value = .{ .void = {} } };
            env.bigints.append(env.allocator, big) catch {};
            big.value.set(i) catch return .{ .value = .{ .void = {} } };
            return .{ .value = .{ .big_int = big } };
        },
        .string => |s| {
            const big = Ast.BigIntValue.fromString(env.allocator, s) catch return .{ .value = .{ .void = {} } };
            env.bigints.append(env.allocator, big) catch {};
            return .{ .value = .{ .big_int = big } };
        },
        .float => return .{ .value = .{ .void = {} } },
        else => return .{ .value = .{ .void = {} } },
    }
}

/// `BigInt.prototype.toString([radix])` — sin sufijo `n`.
/// radix 2..36 → representación en esa base. Fuera de rango → RangeError.
/// Per V8/ES2025: el sufijo `n` es solo del debug format (console.log),
/// `toString()` retorna los dígitos puros (parseable por `BigInt(string)`).
pub fn BigIntToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .big_int) return .{ .value = .{ .void = {} } };
    const big = args[0].big_int;
    // 0 sentinel = "radix inválido" para no contaminar radix 10 default.
    const radix: u8 = if (args.len >= 2) blk: {
        switch (args[1]) {
            .integer => |i| break :blk if (i < 2 or i > 36) @as(u8, 0) else @intCast(i),
            else => break :blk @as(u8, 10),
        }
    } else @as(u8, 10);
    if (radix == 0) {
        // Throw an Error-like object so `e.message` works in catch (matches
        // Node's RangeError, which is an Error object with .name/.message).
        const err_obj = Types.ObjectValue.init(env.allocator) catch {
            return .{ .value = .{ .void = {} } };
        };
        const msg = env.allocator.dupe(u8, "toString() radix argument must be between 2 and 36") catch {
            return .{ .value = .{ .void = {} } };
        };
        env.owned_strings.append(env.allocator, msg) catch {};
        const name = env.allocator.dupe(u8, "RangeError") catch {
            return .{ .value = .{ .void = {} } };
        };
        env.owned_strings.append(env.allocator, name) catch {};
        err_obj.properties.put("name", .{ .string = name }) catch {};
        err_obj.properties.put("message", .{ .string = msg }) catch {};
        env.objects.append(env.allocator, err_obj) catch {};
        env.throw_value = .{ .js_object = err_obj };
        env.throw_hit = true;
        return .{ .value = .{ .void = {} } };
    }
    const digits = big.value.toString(big.allocator, radix, .lower) catch {
        return .{ .value = .{ .void = {} } };
    };
    defer big.allocator.free(digits);
    const result = env.allocator.dupe(u8, digits) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

/// `BigInt.prototype.toLocaleString()` — sin `Intl`, igual a `toString(10)`.
pub fn BigIntToLocaleString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return BigIntToString(args, env);
}

/// `BigInt.prototype.valueOf()` — retorna el BigInt primitivo.
/// Per ES spec, los wrappers BigInt() y los literales BigInt se convierten
/// al mismo tipo primitivo. Como en Lou los literales ya son BigInt, este
/// método es esencialmente identidad (retorna el mismo `*BigIntValue`).
pub fn BigIntValueOf(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .big_int) return .{ .value = .{ .void = {} } };
    return .{ .value = args[0] };
}

/// `BigInt.asUintN(bits, n)` — retorna `n` módulo `2^bits` como BigInt sin signo.
/// Por spec ES: el resultado está siempre en `[0, 2^bits)`.
pub fn BigIntAsUintN(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const bits: usize = switch (args[0]) {
        .integer => |i| if (i < 0) 0 else @intCast(i),
        else => return .{ .value = .{ .void = {} } },
    };
    if (args[1] != .big_int) return .{ .value = .{ .void = {} } };
    const n = args[1].big_int;

    const modulus = Ast.BigIntValue.fromString(env.allocator, "1") catch {
        return .{ .value = .{ .void = {} } };
    };
    env.bigints.append(env.allocator, modulus) catch {};
    if (bits > 0) {
        modulus.value.shiftLeft(&modulus.value, bits) catch return .{ .value = .{ .void = {} } };
    }

    const result = Ast.BigIntValue.fromString(env.allocator, "0") catch {
        return .{ .value = .{ .void = {} } };
    };
    env.bigints.append(env.allocator, result) catch {};
    var quot = Ast.BigIntValue.fromString(env.allocator, "0") catch {
        return .{ .value = .{ .void = {} } };
    };
    env.bigints.append(env.allocator, quot) catch {};

    // divFloor(q, r, a, b) puts floor(a/b) in q and a - q*b in r (with 0 <= r < |b|).
    // r is the non-negative remainder we want.
    quot.value.divFloor(&result.value, &n.value, &modulus.value) catch {
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .big_int = result } };
}

/// `BigInt.asIntN(bits, n)` — retorna `n` módulo `2^bits` interpretado con signo.
/// Por spec ES: el resultado está en `[-2^(bits-1), 2^(bits-1))`.
pub fn BigIntAsIntN(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const bits: usize = switch (args[0]) {
        .integer => |i| if (i < 0) 0 else @intCast(i),
        else => return .{ .value = .{ .void = {} } },
    };
    if (args[1] != .big_int) return .{ .value = .{ .void = {} } };
    const n = args[1].big_int;

    // Compute modulus = 2^bits.
    const modulus = Ast.BigIntValue.fromString(env.allocator, "1") catch {
        return .{ .value = .{ .void = {} } };
    };
    env.bigints.append(env.allocator, modulus) catch {};
    if (bits > 0) {
        modulus.value.shiftLeft(&modulus.value, bits) catch return .{ .value = .{ .void = {} } };
    }

    // r = n mod 2^bits (non-negative, in [0, 2^bits)).
    const r = Ast.BigIntValue.fromString(env.allocator, "0") catch {
        return .{ .value = .{ .void = {} } };
    };
    env.bigints.append(env.allocator, r) catch {};
    var quot = Ast.BigIntValue.fromString(env.allocator, "0") catch {
        return .{ .value = .{ .void = {} } };
    };
    env.bigints.append(env.allocator, quot) catch {};
    quot.value.divFloor(&r.value, &n.value, &modulus.value) catch {
        return .{ .value = .{ .void = {} } };
    };

    // If bits == 0, the result is always 0n (matches Node.js).
    if (bits == 0) {
        return .{ .value = .{ .big_int = r } };
    }

    // half = 2^(bits-1).
    const half = Ast.BigIntValue.fromString(env.allocator, "1") catch {
        return .{ .value = .{ .void = {} } };
    };
    env.bigints.append(env.allocator, half) catch {};
    half.value.shiftLeft(&half.value, bits - 1) catch return .{ .value = .{ .void = {} } };

    // If r >= half, sign-correct by subtracting modulus (wrap into negative range).
    if (r.compare(half) != .lt) {
        r.value.sub(&r.value, &modulus.value) catch {
            return .{ .value = .{ .void = {} } };
        };
    }

    return .{ .value = .{ .big_int = r } };
}

pub const BIGINT_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "toString", .func = BigIntToString },
    .{ .name = "toLocaleString", .func = BigIntToLocaleString },
    .{ .name = "valueOf", .func = BigIntValueOf },
    .{ .name = "asIntN", .func = BigIntAsIntN },
    .{ .name = "asUintN", .func = BigIntAsUintN },
};

pub const BIGINT_OBJECT = Types.BuiltinObjectImpl{
    .name = "BigInt",
    .methods = &BIGINT_METHODS,
};

const testing = std.testing;

test "BigInt constructor with integer" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = BigIntConstructor(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .big_int);
}

test "BigInt constructor with string" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const str = try allocator.dupe(u8, "123");
    env.owned_strings.append(allocator, str) catch {};

    var args = [_]Types.Value{.{ .string = str }};
    const result = BigIntConstructor(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .big_int);
}

test "BigInt constructor with no args returns void" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const result = BigIntConstructor(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "BigInt.toString default radix 10 strips n" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const big = try Ast.BigIntValue.fromString(allocator, "42");
    env.bigints.append(allocator, big) catch {};

    var args = [_]Types.Value{.{ .big_int = big }};
    const result = BigIntToString(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("42", result.value.string);
}

test "BigInt.toString negative" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const big = try Ast.BigIntValue.fromString(allocator, "-42");
    env.bigints.append(allocator, big) catch {};

    var args = [_]Types.Value{.{ .big_int = big }};
    const result = BigIntToString(&args, &env);
    try testing.expectEqualStrings("-42", result.value.string);
}

test "BigInt.toString radix 16" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const big = try Ast.BigIntValue.fromString(allocator, "255");
    env.bigints.append(allocator, big) catch {};

    var radix_arg = [_]Types.Value{ .{ .big_int = big }, .{ .integer = 16 } };
    const result = BigIntToString(&radix_arg, &env);
    try testing.expectEqualStrings("ff", result.value.string);
}

test "BigInt.toString invalid radix 1 throws" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const big = try Ast.BigIntValue.fromString(allocator, "42");
    env.bigints.append(allocator, big) catch {};

    var radix_arg = [_]Types.Value{ .{ .big_int = big }, .{ .integer = 1 } };
    _ = BigIntToString(&radix_arg, &env);
    try testing.expect(env.throw_hit);
}

test "BigInt.toString invalid radix 37 throws" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const big = try Ast.BigIntValue.fromString(allocator, "42");
    env.bigints.append(allocator, big) catch {};

    var radix_arg = [_]Types.Value{ .{ .big_int = big }, .{ .integer = 37 } };
    _ = BigIntToString(&radix_arg, &env);
    try testing.expect(env.throw_hit);
}

fn expectBigIntValue(value: Types.Value, expected: []const u8) !void {
    try testing.expect(value == .big_int);
    const allocator = testing.allocator;
    const s = try value.big_int.value.toString(allocator, 10, .lower);
    defer allocator.free(s);
    try testing.expectEqualStrings(expected, s);
}

test "BigInt.asIntN 8 bits signed boundary" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    {
        const n = try Ast.BigIntValue.fromString(allocator, "255");
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 8 }, .{ .big_int = n } };
        const result = BigIntAsIntN(&args, &env);
        try expectBigIntValue(result.value, "-1");
    }
    {
        const n = try Ast.BigIntValue.fromString(allocator, "128");
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 8 }, .{ .big_int = n } };
        const result = BigIntAsIntN(&args, &env);
        try expectBigIntValue(result.value, "-128");
    }
    {
        const n = try Ast.BigIntValue.fromString(allocator, "127");
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 8 }, .{ .big_int = n } };
        const result = BigIntAsIntN(&args, &env);
        try expectBigIntValue(result.value, "127");
    }
    {
        const n = try Ast.BigIntValue.fromString(allocator, "0");
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 8 }, .{ .big_int = n } };
        const result = BigIntAsIntN(&args, &env);
        try expectBigIntValue(result.value, "0");
    }
}

test "BigInt.asIntN 64 bits full range" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    {
        const n = try Ast.BigIntValue.fromString(allocator, "9223372036854775807"); // 2^63 - 1
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 64 }, .{ .big_int = n } };
        const result = BigIntAsIntN(&args, &env);
        try expectBigIntValue(result.value, "9223372036854775807");
    }
    {
        const n = try Ast.BigIntValue.fromString(allocator, "9223372036854775808"); // 2^63
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 64 }, .{ .big_int = n } };
        const result = BigIntAsIntN(&args, &env);
        try expectBigIntValue(result.value, "-9223372036854775808");
    }
}

test "BigInt.asUintN 8 bits unsigned boundary" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    {
        const n = try Ast.BigIntValue.fromString(allocator, "255");
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 8 }, .{ .big_int = n } };
        const result = BigIntAsUintN(&args, &env);
        try expectBigIntValue(result.value, "255");
    }
    {
        const n = try Ast.BigIntValue.fromString(allocator, "-1");
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 8 }, .{ .big_int = n } };
        const result = BigIntAsUintN(&args, &env);
        try expectBigIntValue(result.value, "255");
    }
    {
        const n = try Ast.BigIntValue.fromString(allocator, "256");
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 8 }, .{ .big_int = n } };
        const result = BigIntAsUintN(&args, &env);
        try expectBigIntValue(result.value, "0");
    }
    {
        const n = try Ast.BigIntValue.fromString(allocator, "-2");
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 8 }, .{ .big_int = n } };
        const result = BigIntAsUintN(&args, &env);
        try expectBigIntValue(result.value, "254");
    }
}

test "BigInt.asUintN 64 bits full range" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    {
        const n = try Ast.BigIntValue.fromString(allocator, "18446744073709551615"); // 2^64 - 1
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 64 }, .{ .big_int = n } };
        const result = BigIntAsUintN(&args, &env);
        try expectBigIntValue(result.value, "18446744073709551615");
    }
    {
        const n = try Ast.BigIntValue.fromString(allocator, "18446744073709551616"); // 2^64
        env.bigints.append(allocator, n) catch {};
        var args = [_]Types.Value{ .{ .integer = 64 }, .{ .big_int = n } };
        const result = BigIntAsUintN(&args, &env);
        try expectBigIntValue(result.value, "0");
    }
}

test "BigInt.asUintN larger than i64" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const big = try Ast.BigIntValue.fromString(allocator, "123456789012345678901234567890");
    env.bigints.append(allocator, big) catch {};
    var args = [_]Types.Value{ .{ .integer = 200 }, .{ .big_int = big } };
    const result = BigIntAsUintN(&args, &env);
    try expectBigIntValue(result.value, "123456789012345678901234567890");
}

test "BigInt.asIntN bits zero returns 0" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const n = try Ast.BigIntValue.fromString(allocator, "5");
    env.bigints.append(allocator, n) catch {};
    var args = [_]Types.Value{ .{ .integer = 0 }, .{ .big_int = n } };
    const result = BigIntAsIntN(&args, &env);
    try expectBigIntValue(result.value, "0");
}

test "BigInt.asIntN round trip via asUintN" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const n = try Ast.BigIntValue.fromString(allocator, "-42");
    env.bigints.append(allocator, n) catch {};
    var signed_args = [_]Types.Value{ .{ .integer = 8 }, .{ .big_int = n } };
    const signed_result = BigIntAsIntN(&signed_args, &env);
    try expectBigIntValue(signed_result.value, "-42");

    var unsigned_args = [_]Types.Value{ .{ .integer = 8 }, signed_result.value };
    const unsigned_result = BigIntAsUintN(&unsigned_args, &env);
    try expectBigIntValue(unsigned_result.value, "214");
}

test "BigInt.asIntN missing args returns void" {
    var env = @import("../../evaluator.zig").Environment.init(testing.allocator, null) catch unreachable;
    defer env.deinit();

    const result = BigIntAsIntN(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "BigInt.asIntN non-bigint second arg returns void" {
    var env = @import("../../evaluator.zig").Environment.init(testing.allocator, null) catch unreachable;
    defer env.deinit();

    var args = [_]Types.Value{ .{ .integer = 8 }, .{ .integer = 255 } };
    const result = BigIntAsIntN(&args, &env);
    try testing.expect(result.value == .void);
}

test "BigInt.asUintN missing args returns void" {
    var env = @import("../../evaluator.zig").Environment.init(testing.allocator, null) catch unreachable;
    defer env.deinit();

    const result = BigIntAsUintN(&[_]Types.Value{}, &env);
    try testing.expect(result.value == .void);
}

test "BigInt.asUintN non-bigint second arg returns void" {
    var env = @import("../../evaluator.zig").Environment.init(testing.allocator, null) catch unreachable;
    defer env.deinit();

    var args = [_]Types.Value{ .{ .integer = 8 }, .{ .string = "255" } };
    const result = BigIntAsUintN(&args, &env);
    try testing.expect(result.value == .void);
}

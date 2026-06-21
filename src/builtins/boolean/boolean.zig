const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

/// `Boolean(value?)` — JS `Boolean()` constructor.
/// Convierte un valor a booleano siguiendo las reglas de ToBoolean del
/// estándar ES (falsy: 0, -0, NaN, "", null, undefined, 0n, false; todo
/// lo demás es truthy).
///
/// Retorna siempre un booleano primitivo. El wrapper para `new Boolean`
/// lo crea el branch de `NewExpression` en `evaluator.zig`.
pub fn BooleanConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) {
        return .{ .value = .{ .boolean = false } };
    }
    return .{ .value = .{ .boolean = toBoolean(args[0]) } };
}

/// `Boolean.prototype.toString()` — retorna "true" o "false".
/// Si el receptor no es un valor booleano (primitivo o wrapper), retorna
/// void. Para wrappers (`@@type="Boolean"`) se lee la propiedad
/// `@@primitive` que fue escrita por `evaluator.zig` al construir el
/// wrapper.
pub fn BooleanToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    const b = switch (args[0]) {
        .boolean => |v| v,
        .js_object => |obj| extractBooleanFromWrapper(obj) orelse return .{ .value = .{ .void = {} } },
        else => return .{ .value = .{ .void = {} } },
    };
    const result = env.allocator.dupe(u8, if (b) "true" else "false") catch {
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

/// `Boolean.prototype.valueOf()` — retorna el primitivo booleano.
pub fn BooleanValueOf(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    return switch (args[0]) {
        .boolean => |v| .{ .value = .{ .boolean = v } },
        .js_object => |obj| {
            const b = extractBooleanFromWrapper(obj) orelse return .{ .value = .{ .void = {} } };
            return .{ .value = .{ .boolean = b } };
        },
        else => .{ .value = .{ .void = {} } },
    };
}

/// Implementación de ToBoolean del estándar ES2025.
/// Coincide con la función `truthy` en `src/vm.zig:2204` pero devuelve
/// `false` explícitamente para object/array (que son truthy en JS).
pub fn toBoolean(v: Types.Value) bool {
    return switch (v) {
        .boolean => |b| b,
        .integer => |i| i != 0,
        .float => |f| f != 0.0 and !std.math.isNan(f),
        .big_int => |big| !big.value.eqlZero(),
        .string => |s| s.len > 0,
        .void, .null, .hole => false,
        else => true,
    };
}

fn extractBooleanFromWrapper(obj: *const Types.ObjectValue) ?bool {
    if (obj.properties.get("@@type")) |tag| {
        if (tag != .string or !std.mem.eql(u8, tag.string, "Boolean")) return null;
    } else return null;
    const prim = obj.properties.get("@@primitive") orelse return null;
    if (prim != .boolean) return null;
    return prim.boolean;
}

/// Crea un wrapper `js_object` con `@@type="Boolean"` y `@@primitive`
/// conteniendo el booleano. Usado por el branch de `NewExpression` en
/// `evaluator.zig` cuando el nombre del builtin es `"Boolean"`.
/// Retorna `null` si la entrada no es un valor booleano.
pub fn makeBooleanWrapper(env: *Types.Environment, v: Types.Value) !?Types.Value {
    if (v != .boolean) return null;
    const obj = try Types.ObjectValue.init(env.allocator);
    errdefer obj.deinit();
    const tag = try env.allocator.dupe(u8, "Boolean");
    errdefer env.allocator.free(tag);
    try env.owned_strings.append(env.allocator, tag);
    try obj.properties.put("@@type", .{ .string = tag });
    try obj.properties.put("@@primitive", v);
    try env.objects.append(env.allocator, obj);
    return Types.Value{ .js_object = obj };
}

pub const BOOLEAN_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "toString", .func = BooleanToString },
    .{ .name = "valueOf", .func = BooleanValueOf },
};

pub const BOOLEAN_OBJECT = Types.BuiltinObjectImpl{
    .name = "Boolean",
    .methods = &BOOLEAN_METHODS,
};

const testing = std.testing;

test "Boolean() with no args returns false" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const result = BooleanConstructor(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(!result.value.boolean);
}

test "Boolean(true) returns true" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .boolean = true }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(result.value.boolean);
}

test "Boolean(1) is truthy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .integer = 1 }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(result.value.boolean);
}

test "Boolean(0) is falsy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .integer = 0 }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(!result.value.boolean);
}

test "Boolean(-0) is falsy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .float = -0.0 }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(!result.value.boolean);
}

test "Boolean(NaN) is falsy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .float = std.math.nan(f64) }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(!result.value.boolean);
}

test "Boolean('') is falsy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const s = try testing.allocator.dupe(u8, "");
    defer testing.allocator.free(s);
    env.owned_strings.append(testing.allocator, s) catch {};

    var args = [_]Types.Value{.{ .string = s }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(!result.value.boolean);
}

test "Boolean('hello') is truthy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const s = try testing.allocator.dupe(u8, "hello");
    env.owned_strings.append(testing.allocator, s) catch {};

    var args = [_]Types.Value{.{ .string = s }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(result.value.boolean);
}

test "Boolean(null) is falsy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .null = {} }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(!result.value.boolean);
}

test "Boolean(undefined) is falsy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .void = {} }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(!result.value.boolean);
}

test "Boolean(0n) is falsy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const big = try Ast.BigIntValue.fromString(testing.allocator, "0");
    env.bigints.append(testing.allocator, big) catch {};

    var args = [_]Types.Value{.{ .big_int = big }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(!result.value.boolean);
}

test "Boolean(42n) is truthy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const big = try Ast.BigIntValue.fromString(testing.allocator, "42");
    env.bigints.append(testing.allocator, big) catch {};

    var args = [_]Types.Value{.{ .big_int = big }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(result.value.boolean);
}

test "Boolean({}) and Boolean([]) are truthy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const obj = try Types.ObjectValue.init(testing.allocator);
    env.objects.append(testing.allocator, obj) catch {};

    var obj_args = [_]Types.Value{.{ .js_object = obj }};
    try testing.expect(BooleanConstructor(&obj_args, &env).value.boolean);

    const arr = try Ast.ArrayObject.init(testing.allocator);
    env.arrays.append(testing.allocator, arr) catch {};

    var arr_args = [_]Types.Value{.{ .array = arr }};
    try testing.expect(BooleanConstructor(&arr_args, &env).value.boolean);
}

test "Boolean(-1) is truthy" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .integer = -1 }};
    const result = BooleanConstructor(&args, &env);
    try testing.expect(result.value.boolean);
}

test "Boolean('0') and Boolean('false') are truthy (non-empty string)" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const s0 = try testing.allocator.dupe(u8, "0");
    env.owned_strings.append(testing.allocator, s0) catch {};
    var a0 = [_]Types.Value{.{ .string = s0 }};
    try testing.expect(BooleanConstructor(&a0, &env).value.boolean);

    const sf = try testing.allocator.dupe(u8, "false");
    env.owned_strings.append(testing.allocator, sf) catch {};
    var af = [_]Types.Value{.{ .string = sf }};
    try testing.expect(BooleanConstructor(&af, &env).value.boolean);
}

test "Boolean.prototype.toString true/false" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var t_args = [_]Types.Value{.{ .boolean = true }};
    const t_result = BooleanToString(&t_args, &env);
    try testing.expectEqualStrings("true", t_result.value.string);

    var f_args = [_]Types.Value{.{ .boolean = false }};
    const f_result = BooleanToString(&f_args, &env);
    try testing.expectEqualStrings("false", f_result.value.string);
}

test "Boolean.prototype.valueOf returns primitive" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var t_args = [_]Types.Value{.{ .boolean = true }};
    const t_result = BooleanValueOf(&t_args, &env);
    try testing.expect(t_result.value == .boolean);
    try testing.expect(t_result.value.boolean);

    var f_args = [_]Types.Value{.{ .boolean = false }};
    const f_result = BooleanValueOf(&f_args, &env);
    try testing.expect(f_result.value == .boolean);
    try testing.expect(!f_result.value.boolean);
}

test "Boolean.prototype methods on wrapper js_object" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const obj = try Types.ObjectValue.init(testing.allocator);
    env.objects.append(testing.allocator, obj) catch {};

    const tag = try testing.allocator.dupe(u8, "Boolean");
    env.owned_strings.append(testing.allocator, tag) catch {};
    try obj.properties.put("@@type", .{ .string = tag });
    try obj.properties.put("@@primitive", .{ .boolean = true });

    var t_args = [_]Types.Value{.{ .js_object = obj }};
    const t_result = BooleanToString(&t_args, &env);
    try testing.expectEqualStrings("true", t_result.value.string);

    const v_result = BooleanValueOf(&t_args, &env);
    try testing.expect(v_result.value == .boolean);
    try testing.expect(v_result.value.boolean);
}

test "Boolean.prototype methods on non-boolean return void" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var i_args = [_]Types.Value{.{ .integer = 1 }};
    try testing.expect(BooleanToString(&i_args, &env).value == .void);
    try testing.expect(BooleanValueOf(&i_args, &env).value == .void);

    var n_args = [_]Types.Value{};
    try testing.expect(BooleanToString(&n_args, &env).value == .void);
    try testing.expect(BooleanValueOf(&n_args, &env).value == .void);
}

test "extractBooleanFromWrapper rejects non-Boolean @@type" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const obj = try Types.ObjectValue.init(testing.allocator);
    env.objects.append(testing.allocator, obj) catch {};

    const tag = try testing.allocator.dupe(u8, "Set");
    env.owned_strings.append(testing.allocator, tag) catch {};
    try obj.properties.put("@@type", .{ .string = tag });
    try obj.properties.put("@@primitive", .{ .boolean = true });

    try testing.expect(extractBooleanFromWrapper(obj) == null);
    var args = [_]Types.Value{.{ .js_object = obj }};
    try testing.expect(BooleanToString(&args, &env).value == .void);
}

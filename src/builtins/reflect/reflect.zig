const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;
const throwError = @import("../error.zig").throwError;

fn newObject(env: *Types.Environment) ?*Ast.ObjectValue {
    const obj = Ast.ObjectValue.init(env.allocator) catch return null;
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return null;
    };
    return obj;
}

fn newArray(env: *Types.Environment) ?*Ast.ArrayObject {
    const arr = Ast.ArrayObject.init(env.allocator) catch return null;
    env.arrays.append(env.allocator, arr) catch {
        arr.deinit();
        return null;
    };
    return arr;
}

fn keyString(env: *Types.Environment, v: Types.Value) ?[]const u8 {
    return switch (v) {
        .string => |s| s,
        .integer => |i| blk: {
            const s = std.fmt.allocPrint(env.allocator, "{d}", .{i}) catch return null;
            env.owned_strings.append(env.allocator, s) catch {};
            break :blk s;
        },
        .float => |f| blk: {
            const s = std.fmt.allocPrint(env.allocator, "{d}", .{f}) catch return null;
            env.owned_strings.append(env.allocator, s) catch {};
            break :blk s;
        },
        .symbol => |sym| sym.description,
        else => null,
    };
}

fn isAccessor(v: Types.Value) bool {
    if (v != .js_object) return false;
    const native = v.js_object.properties.get("@@native") orelse return false;
    return native == .string and std.mem.eql(u8, native.string, "Accessor");
}

fn getProperty(target: Types.Value, key: []const u8, env: *Types.Environment) Types.Value {
    switch (target) {
        .js_object => |o| {
            var cur: ?*Ast.ObjectValue = o;
            while (cur) |c| {
                if (c.properties.get(key)) |v| {
                    if (isAccessor(v)) {
                        const getter = v.js_object.properties.get("get") orelse return .{ .void = {} };
                        const callFn = @import("../../evaluator.zig").callFunctionValue;
                        return callFn(getter, &[_]Types.Value{}, env, target) catch .{ .void = {} };
                    }
                    return v;
                }
                cur = c.prototype;
            }
            return .{ .void = {} };
        },
        .array => |arr| {
            if (std.mem.eql(u8, key, "length")) return .{ .integer = @intCast(arr.elements.items.len) };
            const idx = std.fmt.parseInt(usize, key, 10) catch return .{ .void = {} };
            if (idx >= arr.elements.items.len) return .{ .void = {} };
            const v = arr.elements.items[idx];
            if (v == .hole) return .{ .void = {} };
            return v;
        },
        .string => |s| {
            if (std.mem.eql(u8, key, "length")) return .{ .integer = @intCast(s.len) };
            const idx = std.fmt.parseInt(usize, key, 10) catch return .{ .void = {} };
            if (idx >= s.len) return .{ .void = {} };
            const one = env.allocator.dupe(u8, s[idx .. idx + 1]) catch return .{ .void = {} };
            env.owned_strings.append(env.allocator, one) catch {};
            return .{ .string = one };
        },
        .object => |ptr| {
            const impl: *const Types.BuiltinObjectImpl = @ptrCast(@alignCast(ptr));
            if (impl.getProperty(key)) |v| return v;
            return .{ .void = {} };
        },
        else => return .{ .void = {} },
    }
}

fn setProperty(target: Types.Value, key: []const u8, value: Types.Value) bool {
    switch (target) {
        .js_object => |o| {
            if (o.frozen) return false;
            if (!o.extensible and o.properties.get(key) == null) return false;
            o.properties.put(key, value) catch return false;
            return true;
        },
        .array => |arr| {
            const idx = std.fmt.parseInt(usize, key, 10) catch return false;
            arr.set(idx, value) catch return false;
            return true;
        },
        else => return false,
    }
}

fn hasProperty(target: Types.Value, key: []const u8) bool {
    switch (target) {
        .js_object => |o| {
            var cur: ?*Ast.ObjectValue = o;
            while (cur) |c| {
                if (c.properties.get(key) != null) return true;
                cur = c.prototype;
            }
            return false;
        },
        .array => |arr| {
            if (std.mem.eql(u8, key, "length")) return true;
            const idx = std.fmt.parseInt(usize, key, 10) catch return false;
            return idx < arr.elements.items.len;
        },
        .string => |s| {
            if (std.mem.eql(u8, key, "length")) return true;
            const idx = std.fmt.parseInt(usize, key, 10) catch return false;
            return idx < s.len;
        },
        else => return false,
    }
}

fn isObjectValue(v: Types.Value) bool {
    return switch (v) {
        .js_object, .array, .function, .closure, .generator, .regexp => true,
        else => false,
    };
}

/// Throw the ECMAScript TypeError for a non-object target.
fn requireObject(env: *Types.Environment, v: Types.Value, method: []const u8) bool {
    if (isObjectValue(v)) return true;
    const msg = std.fmt.allocPrint(env.allocator, "Reflect.{s} called on non-object", .{method}) catch return false;
    defer env.allocator.free(msg);
    _ = throwError(env, "TypeError", .{ .string = msg });
    return false;
}
/// `Reflect.get(target, key)` — own or inherited property, invoking getters.
pub fn Get(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or !requireObject(env, args[0], "get")) return .{ .value = .{ .void = {} } };
    const key = keyString(env, args[1]) orelse return .{ .value = .{ .void = {} } };
    return .{ .value = getProperty(args[0], key, env) };
}

/// `Reflect.set(target, key, value)` — returns whether the write succeeded.
pub fn Set(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 3 or !requireObject(env, args[0], "set")) return .{ .value = .{ .boolean = false } };
    const key = keyString(env, args[1]) orelse return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = setProperty(args[0], key, args[2]) } };
}

/// `Reflect.has(target, key)` — same as `key in target`.
pub fn Has(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or !requireObject(env, args[0], "has")) return .{ .value = .{ .boolean = false } };
    const key = keyString(env, args[1]) orelse return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = hasProperty(args[0], key) } };
}

/// `Reflect.deleteProperty(target, key)` — same as `delete target[key]`.
pub fn DeleteProperty(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or !requireObject(env, args[0], "deleteProperty")) return .{ .value = .{ .boolean = true } };
    const key = keyString(env, args[1]) orelse return .{ .value = .{ .boolean = true } };
    switch (args[0]) {
        .js_object => |o| {
            _ = o.properties.remove(key);
        },
        .array => |arr| {
            const idx = std.fmt.parseInt(usize, key, 10) catch return .{ .value = .{ .boolean = true } };
            if (idx < arr.elements.items.len) arr.elements.items[idx] = .{ .hole = {} };
        },
        else => {},
    }
    return .{ .value = .{ .boolean = true } };
}

/// `Reflect.ownKeys(target)` — string-keyed own properties.
pub fn OwnKeys(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const result = newArray(env) orelse return .{ .value = .{ .void = {} } };
    if (args.len == 0 or !requireObject(env, args[0], "ownKeys")) return .{ .value = .{ .array = result } };
    switch (args[0]) {
        .js_object => |o| {
            const keys = o.getForInKeys(env.allocator, &env.arrays) catch return .{ .value = .{ .array = result } };
            for (keys.elements.items) |k| result.elements.append(env.allocator, k) catch {};
        },
        .array => |arr| {
            var i: usize = 0;
            while (i < arr.elements.items.len) : (i += 1) {
                const s = std.fmt.allocPrint(env.allocator, "{d}", .{i}) catch continue;
                env.owned_strings.append(env.allocator, s) catch {};
                result.elements.append(env.allocator, .{ .string = s }) catch {};
            }
            result.elements.append(env.allocator, .{ .string = "length" }) catch {};
        },
        else => {},
    }
    return .{ .value = .{ .array = result } };
}

/// `Reflect.apply(target, thisArg, argsArray)`.
pub fn Apply(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 3 or args[2] != .array) return .{ .value = .{ .void = {} } };
    const callFn = @import("../../evaluator.zig").callFunctionValue;
    const this_val: ?Types.Value = if (args[1] == .void) null else args[1];
    const result = callFn(args[0], args[2].array.elements.items, env, this_val) catch return .{ .value = .{ .void = {} } };
    return .{ .value = result };
}

/// `Reflect.construct(target, argsArray)` — minimal constructor call.
pub fn Construct(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or args[1] != .array) return .{ .value = .{ .void = {} } };
    const obj = newObject(env) orelse return .{ .value = .{ .void = {} } };
    const this_val = Types.Value{ .js_object = obj };
    const callFn = @import("../../evaluator.zig").callFunctionValue;
    const result = callFn(args[0], args[1].array.elements.items, env, this_val) catch return .{ .value = .{ .js_object = obj } };
    return switch (result) {
        .js_object, .array, .function, .closure, .generator => .{ .value = result },
        else => .{ .value = .{ .js_object = obj } },
    };
}

/// `Reflect.defineProperty(target, key, descriptor)` — data descriptors.
pub fn DefineProperty(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 3 or args[0] != .js_object or args[2] != .js_object) {
        if (args.len < 3 or !requireObject(env, args[0], "defineProperty")) return .{ .value = .{ .boolean = false } };
        return .{ .value = .{ .boolean = false } };
    }
    const key = keyString(env, args[1]) orelse return .{ .value = .{ .boolean = false } };
    const target = args[0].js_object;
    if (target.frozen) return .{ .value = .{ .boolean = false } };
    if (!target.extensible and target.properties.get(key) == null) {
        return .{ .value = .{ .boolean = false } };
    }
    if (args[2].js_object.properties.get("value")) |v| {
        target.properties.put(key, v) catch return .{ .value = .{ .boolean = false } };
    }
    return .{ .value = .{ .boolean = true } };
}

/// `Reflect.getOwnPropertyDescriptor(target, key)`.
pub fn GetOwnPropertyDescriptor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or !requireObject(env, args[0], "getOwnPropertyDescriptor")) return .{ .value = .{ .void = {} } };
    if (args[0] != .js_object) return .{ .value = .{ .void = {} } };
    const key = keyString(env, args[1]) orelse return .{ .value = .{ .void = {} } };
    const value = args[0].js_object.properties.get(key) orelse return .{ .value = .{ .void = {} } };
    const desc = newObject(env) orelse return .{ .value = .{ .void = {} } };
    desc.properties.put("value", value) catch {};
    desc.properties.put("writable", .{ .boolean = true }) catch {};
    desc.properties.put("enumerable", .{ .boolean = true }) catch {};
    desc.properties.put("configurable", .{ .boolean = true }) catch {};
    return .{ .value = .{ .js_object = desc } };
}

/// `Reflect.getPrototypeOf(target)`.
pub fn GetPrototypeOf(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0 or !requireObject(env, args[0], "getPrototypeOf")) return .{ .value = .{ .null = {} } };
    if (args[0] != .js_object) return .{ .value = .{ .null = {} } };
    if (args[0].js_object.prototype) |proto| return .{ .value = .{ .js_object = proto } };
    return .{ .value = .{ .null = {} } };
}

/// `Reflect.setPrototypeOf(target, proto)`.
pub fn SetPrototypeOf(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or !requireObject(env, args[0], "setPrototypeOf")) return .{ .value = .{ .boolean = false } };
    if (args[0] != .js_object) return .{ .value = .{ .boolean = false } };
    if (args[1] == .null) {
        args[0].js_object.prototype = null;
        return .{ .value = .{ .boolean = true } };
    }
    if (args[1] != .js_object) return .{ .value = .{ .boolean = false } };
    args[0].js_object.prototype = args[1].js_object;
    return .{ .value = .{ .boolean = true } };
}

/// `Reflect.isExtensible(target)`.
pub fn IsExtensible(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0 or !requireObject(env, args[0], "isExtensible")) return .{ .value = .{ .boolean = false } };
    if (args[0] != .js_object) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = args[0].js_object.extensible } };
}

/// `Reflect.preventExtensions(target)`.
pub fn PreventExtensions(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0 or !requireObject(env, args[0], "preventExtensions")) return .{ .value = .{ .boolean = true } };
    if (args[0] == .js_object) args[0].js_object.extensible = false;
    return .{ .value = .{ .boolean = true } };
}

const testing = std.testing;

test "Reflect get, set, has and deleteProperty" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const obj = newObject(&env) orelse return error.OutOfMemory;
    var set_args = [_]Types.Value{ .{ .js_object = obj }, .{ .string = "a" }, .{ .integer = 1 } };
    try testing.expect(Set(&set_args, &env).value.boolean);

    var get_args = [_]Types.Value{ .{ .js_object = obj }, .{ .string = "a" } };
    const got = Get(&get_args, &env);
    try testing.expect(got.value == .integer);
    try testing.expectEqual(@as(i64, 1), got.value.integer);

    var has_args = [_]Types.Value{ .{ .js_object = obj }, .{ .string = "a" } };
    try testing.expect(Has(&has_args, &env).value.boolean);

    var del_args = [_]Types.Value{ .{ .js_object = obj }, .{ .string = "a" } };
    try testing.expect(DeleteProperty(&del_args, &env).value.boolean);
    try testing.expect(!Has(&has_args, &env).value.boolean);
}

test "Reflect getPrototypeOf and setPrototypeOf" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const proto = newObject(&env) orelse return error.OutOfMemory;
    const obj = newObject(&env) orelse return error.OutOfMemory;
    var set_args = [_]Types.Value{ .{ .js_object = obj }, .{ .js_object = proto } };
    try testing.expect(SetPrototypeOf(&set_args, &env).value.boolean);

    var get_args = [_]Types.Value{.{ .js_object = obj }};
    const got = GetPrototypeOf(&get_args, &env);
    try testing.expect(got.value == .js_object);
    try testing.expect(got.value.js_object == proto);
}

test "Reflect throws TypeError for non-object targets" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .integer = 1 }, .{ .string = "x" } };
    _ = Get(&args, &env);
    try testing.expect(env.throw_hit);
}
pub const REFLECT_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "get", .func = Get },
    .{ .name = "set", .func = Set },
    .{ .name = "has", .func = Has },
    .{ .name = "deleteProperty", .func = DeleteProperty },
    .{ .name = "ownKeys", .func = OwnKeys },
    .{ .name = "apply", .func = Apply },
    .{ .name = "construct", .func = Construct },
    .{ .name = "defineProperty", .func = DefineProperty },
    .{ .name = "getOwnPropertyDescriptor", .func = GetOwnPropertyDescriptor },
    .{ .name = "getPrototypeOf", .func = GetPrototypeOf },
    .{ .name = "setPrototypeOf", .func = SetPrototypeOf },
    .{ .name = "isExtensible", .func = IsExtensible },
    .{ .name = "preventExtensions", .func = PreventExtensions },
};

pub const REFLECT_OBJECT = Types.BuiltinObjectImpl{
    .name = "Reflect",
    .methods = &REFLECT_METHODS,
};

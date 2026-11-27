const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn isObject(v: Types.Value) bool {
    return switch (v) {
        .js_object, .array, .function, .closure, .generator, .iterator, .array_iterator, .regexp => true,
        else => false,
    };
}

/// Convert a property key to a string, registering allocated keys with the
/// environment so they live as long as the program.
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

fn isNumber(v: Types.Value) bool {
    return v == .integer or v == .float;
}

fn numOf(v: Types.Value) f64 {
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => 0,
    };
}

fn sameValue(a: Types.Value, b: Types.Value) bool {
    if (isNumber(a) and isNumber(b)) {
        const x = numOf(a);
        const y = numOf(b);
        if (std.math.isNan(x) and std.math.isNan(y)) return true;
        if (x == 0 and y == 0) return std.math.signbit(x) == std.math.signbit(y);
        return x == y;
    }
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .string => |s| std.mem.eql(u8, s, b.string),
        .boolean => |v| v == b.boolean,
        .big_int => |v| v.compare(b.big_int) == .eq,
        .js_object => a.js_object == b.js_object,
        .object => a.object == b.object,
        .array => a.array == b.array,
        .function => a.function == b.function,
        .closure => a.closure == b.closure,
        .generator => a.generator == b.generator,
        .iterator => a.iterator == b.iterator,
        .array_iterator => a.array_iterator == b.array_iterator,
        .regexp => a.regexp == b.regexp,
        .symbol => a.symbol == b.symbol,
        .void, .null, .hole => true,
        else => false,
    };
}

/// `Object.is(a, b)` — SameValue.
pub fn Is(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = sameValue(args[0], args[1]) } };
}

/// `Object.fromEntries(iterable)` — array of `[key, value]` pairs or a Map.
pub fn FromEntries(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const obj = newObject(env) orelse return .{ .value = .{ .void = {} } };
    if (args.len == 0) return .{ .value = .{ .js_object = obj } };

    const source = args[0];
    const entries: ?*Ast.ArrayObject = switch (source) {
        .array => |arr| arr,
        .js_object => |o| blk: {
            const t = o.properties.get("@@type");
            if (t != null and t.? == .string and std.mem.eql(u8, t.?.string, "Map")) {
                if (o.properties.get("entries")) |e| {
                    if (e == .array) break :blk e.array;
                }
            }
            if (o.properties.get("entries")) |e| {
                if (e == .array) break :blk e.array;
            }
            break :blk null;
        },
        else => null,
    };
    if (entries) |arr| {
        for (arr.elements.items) |pair| {
            if (pair != .array or pair.array.elements.items.len < 2) continue;
            const k = keyString(env, pair.array.elements.items[0]) orelse continue;
            obj.properties.put(k, pair.array.elements.items[1]) catch {};
        }
    }
    return .{ .value = .{ .js_object = obj } };
}

/// `Object.getOwnPropertyNames(obj)` — own keys, integer indices first.
pub fn GetOwnPropertyNames(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0 or args[0] != .js_object) {
        const empty = newArray(env) orelse return .{ .value = .{ .void = {} } };
        return .{ .value = .{ .array = empty } };
    }
    const keys = args[0].js_object.getForInKeys(env.allocator, &env.arrays) catch {
        return .{ .value = .{ .void = {} } };
    };
    return .{ .value = .{ .array = keys } };
}

fn descriptorFor(env: *Types.Environment, value: Types.Value) ?*Ast.ObjectValue {
    const desc = newObject(env) orelse return null;
    desc.properties.put("value", value) catch {};
    desc.properties.put("writable", .{ .boolean = true }) catch {};
    desc.properties.put("enumerable", .{ .boolean = true }) catch {};
    desc.properties.put("configurable", .{ .boolean = true }) catch {};
    return desc;
}

/// `Object.getOwnPropertyDescriptor(obj, key)`.
pub fn GetOwnPropertyDescriptor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or args[0] != .js_object) return .{ .value = .{ .void = {} } };
    const key = keyString(env, args[1]) orelse return .{ .value = .{ .void = {} } };
    const value = args[0].js_object.properties.get(key) orelse return .{ .value = .{ .void = {} } };
    const desc = descriptorFor(env, value) orelse return .{ .value = .{ .void = {} } };
    return .{ .value = .{ .js_object = desc } };
}

/// `Object.getOwnPropertyDescriptors(obj)`.
pub fn GetOwnPropertyDescriptors(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const result = newObject(env) orelse return .{ .value = .{ .void = {} } };
    if (args.len == 0 or args[0] != .js_object) return .{ .value = .{ .js_object = result } };
    const ordered = args[0].js_object.getForInKeys(env.allocator, &env.arrays) catch return .{ .value = .{ .js_object = result } };
    for (ordered.elements.items) |key_val| {
        const key = key_val.string;
        const value = args[0].js_object.properties.get(key) orelse continue;
        const desc = descriptorFor(env, value) orelse continue;
        result.properties.put(key, .{ .js_object = desc }) catch {};
    }
    return .{ .value = .{ .js_object = result } };
}

/// `Object.getOwnPropertySymbols(obj)` — Lou stores symbol keys as strings,
/// so there are no own symbol keys to report.
pub fn GetOwnPropertySymbols(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = args;
    const empty = newArray(env) orelse return .{ .value = .{ .void = {} } };
    return .{ .value = .{ .array = empty } };
}

/// `Object.defineProperty(obj, key, descriptor)` — data descriptors only.
pub fn DefineProperty(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 3 or args[0] != .js_object) return .{ .value = .{ .void = {} } };
    const key = keyString(env, args[1]) orelse return .{ .value = .{ .js_object = args[0].js_object } };
    if (args[2] == .js_object) {
        if (args[2].js_object.properties.get("value")) |v| {
            args[0].js_object.properties.put(key, v) catch {};
        }
    }
    return .{ .value = .{ .js_object = args[0].js_object } };
}

pub fn Freeze(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .void = {} } };
    if (args[0] == .js_object) {
        args[0].js_object.frozen = true;
        args[0].js_object.sealed = true;
        args[0].js_object.extensible = false;
    }
    return .{ .value = args[0] };
}

pub fn Seal(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .void = {} } };
    if (args[0] == .js_object) {
        args[0].js_object.sealed = true;
        args[0].js_object.extensible = false;
    }
    return .{ .value = args[0] };
}

pub fn PreventExtensions(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .void = {} } };
    if (args[0] == .js_object) args[0].js_object.extensible = false;
    return .{ .value = args[0] };
}

pub fn IsExtensible(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0 or args[0] != .js_object) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = args[0].js_object.extensible } };
}

pub fn IsSealed(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .boolean = true } };
    if (args[0] != .js_object) return .{ .value = .{ .boolean = true } };
    return .{ .value = .{ .boolean = args[0].js_object.sealed } };
}

pub fn IsFrozen(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .boolean = true } };
    if (args[0] != .js_object) return .{ .value = .{ .boolean = true } };
    return .{ .value = .{ .boolean = args[0].js_object.frozen } };
}

const testing = std.testing;

test "Object.is distinguishes -0 and treats NaN as equal" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    var nan_args = [_]Types.Value{ .{ .float = std.math.nan(f64) }, .{ .float = std.math.nan(f64) } };
    const nan = Is(&nan_args, &env);
    try testing.expect(nan.value.boolean);
    var zero_args = [_]Types.Value{ .{ .integer = 0 }, .{ .float = -0.0 } };
    const zero = Is(&zero_args, &env);
    try testing.expect(!zero.value.boolean);
}
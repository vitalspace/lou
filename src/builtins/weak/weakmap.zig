const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;
const throwError = @import("../error.zig").throwError;

fn isWeakKey(v: Types.Value) bool {
    return switch (v) {
        .js_object, .array, .function, .closure, .generator, .iterator, .array_iterator, .regexp => true,
        else => false,
    };
}

fn sameKey(a: Types.Value, b: Types.Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .js_object => a.js_object == b.js_object,
        .array => a.array == b.array,
        .function => a.function == b.function,
        .closure => a.closure == b.closure,
        .generator => a.generator == b.generator,
        .iterator => a.iterator == b.iterator,
        .array_iterator => a.array_iterator == b.array_iterator,
        .regexp => a.regexp == b.regexp,
        else => false,
    };
}

fn getWeakMap(args: []Types.Value) ?*Ast.ObjectValue {
    if (args.len == 0 or args[0] != .js_object) return null;
    const obj = args[0].js_object;
    const t = obj.properties.get("@@type") orelse return null;
    if (t != .string or !std.mem.eql(u8, t.string, "WeakMap")) return null;
    return obj;
}

fn getEntries(obj: *Ast.ObjectValue) ?*Ast.ArrayObject {
    if (obj.properties.get("entries")) |v| {
        if (v == .array) return v.array;
    }
    return null;
}

fn findIndex(entries: *Ast.ArrayObject, key: Types.Value) ?usize {
    for (entries.elements.items, 0..) |pair, i| {
        if (pair != .array or pair.array.elements.items.len < 1) continue;
        if (sameKey(pair.array.elements.items[0], key)) return i;
    }
    return null;
}

/// `new WeakMap([iterable])` — keys must be objects.
pub fn WeakMapConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const obj = Ast.ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };

    const entries = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.arrays.append(env.allocator, entries) catch {
        entries.deinit();
        return .{ .value = .{ .void = {} } };
    };

    obj.properties.put("@@type", .{ .string = "WeakMap" }) catch {};
    obj.properties.put("entries", .{ .array = entries }) catch {};

    if (args.len >= 1 and args[0] == .array) {
        for (args[0].array.elements.items) |elem| {
            if (elem != .array or elem.array.elements.items.len < 2) continue;
            const key = elem.array.elements.items[0];
            if (!isWeakKey(key)) {
                _ = throwError(env, "TypeError", .{ .string = "Invalid value used as weak map key" });
                return .{ .value = .{ .void = {} } };
            }
            const pair = Ast.ArrayObject.init(env.allocator) catch continue;
            env.arrays.append(env.allocator, pair) catch {
                pair.deinit();
                continue;
            };
            pair.elements.append(env.allocator, key) catch {};
            pair.elements.append(env.allocator, elem.array.elements.items[1]) catch {};
            entries.elements.append(env.allocator, .{ .array = pair }) catch {};
        }
    }

    return .{ .value = .{ .js_object = obj } };
}

pub fn WeakMapSet(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const this = getWeakMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = getEntries(this) orelse return .{ .value = .{ .void = {} } };
    if (args.len < 2) {
        _ = throwError(env, "TypeError", .{ .string = "Invalid value used as weak map key" });
        return .{ .value = .{ .void = {} } };
    }
    const key = args[1];
    if (!isWeakKey(key)) {
        _ = throwError(env, "TypeError", .{ .string = "Invalid value used as weak map key" });
        return .{ .value = .{ .void = {} } };
    }

    if (findIndex(entries, key)) |i| {
        const pair = entries.elements.items[i];
        pair.array.elements.items[1] = args[2];
    } else {
        const pair = Ast.ArrayObject.init(env.allocator) catch return .{ .value = args[0] };
        env.arrays.append(env.allocator, pair) catch {
            pair.deinit();
            return .{ .value = args[0] };
        };
        pair.elements.append(env.allocator, key) catch {};
        pair.elements.append(env.allocator, args[2]) catch {};
        entries.elements.append(env.allocator, .{ .array = pair }) catch {};
    }
    return .{ .value = args[0] };
}

pub fn WeakMapGet(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const this = getWeakMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = getEntries(this) orelse return .{ .value = .{ .void = {} } };
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const i = findIndex(entries, args[1]) orelse return .{ .value = .{ .void = {} } };
    const pair = entries.elements.items[i];
    if (pair.array.elements.items.len < 2) return .{ .value = .{ .void = {} } };
    return .{ .value = pair.array.elements.items[1] };
}

pub fn WeakMapHas(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const this = getWeakMap(args) orelse return .{ .value = .{ .boolean = false } };
    const entries = getEntries(this) orelse return .{ .value = .{ .boolean = false } };
    if (args.len < 2) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = findIndex(entries, args[1]) != null } };
}

pub fn WeakMapDelete(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const this = getWeakMap(args) orelse return .{ .value = .{ .boolean = false } };
    const entries = getEntries(this) orelse return .{ .value = .{ .boolean = false } };
    if (args.len < 2) return .{ .value = .{ .boolean = false } };
    const i = findIndex(entries, args[1]) orelse return .{ .value = .{ .boolean = false } };
    _ = entries.elements.orderedRemove(i);
    return .{ .value = .{ .boolean = true } };
}

const WEAKMAP_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "set", .func = WeakMapSet },
    .{ .name = "get", .func = WeakMapGet },
    .{ .name = "has", .func = WeakMapHas },
    .{ .name = "delete", .func = WeakMapDelete },
};

pub const WEAKMAP_OBJECT = Types.BuiltinObjectImpl{
    .name = "WeakMap",
    .methods = &WEAKMAP_METHODS,
};

const testing = std.testing;

test "WeakMap stores and deletes object keys" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const map = WeakMapConstructor(&.{}, &env).value;
    const key = Ast.ObjectValue.init(allocator) catch return;
    defer key.deinit();

    var set_args = [_]Types.Value{ map, .{ .js_object = key }, .{ .integer = 7 } };
    _ = WeakMapSet(&set_args, &env);
    var get_args = [_]Types.Value{ map, .{ .js_object = key } };
    const got = WeakMapGet(&get_args, &env);
    try testing.expectEqual(@as(i64, 7), got.value.integer);
    var del_args = [_]Types.Value{ map, .{ .js_object = key } };
    const deleted = WeakMapDelete(&del_args, &env);
    try testing.expect(deleted.value.boolean);
}
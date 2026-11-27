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

fn getWeakSet(args: []Types.Value) ?*Ast.ObjectValue {
    if (args.len == 0 or args[0] != .js_object) return null;
    const obj = args[0].js_object;
    const t = obj.properties.get("@@type") orelse return null;
    if (t != .string or !std.mem.eql(u8, t.string, "WeakSet")) return null;
    return obj;
}

fn getValues(obj: *Ast.ObjectValue) ?*Ast.ArrayObject {
    if (obj.properties.get("values")) |v| {
        if (v == .array) return v.array;
    }
    return null;
}

fn findIndex(values: *Ast.ArrayObject, key: Types.Value) ?usize {
    for (values.elements.items, 0..) |item, i| {
        if (sameKey(item, key)) return i;
    }
    return null;
}

/// `new WeakSet([iterable])` — values must be objects.
pub fn WeakSetConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const obj = Ast.ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };

    const values = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.arrays.append(env.allocator, values) catch {
        values.deinit();
        return .{ .value = .{ .void = {} } };
    };

    obj.properties.put("@@type", .{ .string = "WeakSet" }) catch {};
    obj.properties.put("values", .{ .array = values }) catch {};

    if (args.len >= 1 and args[0] == .array) {
        for (args[0].array.elements.items) |item| {
            if (!isWeakKey(item)) {
                _ = throwError(env, "TypeError", .{ .string = "Invalid value used in weak set" });
                return .{ .value = .{ .void = {} } };
            }
            values.elements.append(env.allocator, item) catch {};
        }
    }

    return .{ .value = .{ .js_object = obj } };
}

pub fn WeakSetAdd(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const this = getWeakSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(this) orelse return .{ .value = .{ .void = {} } };
    if (args.len < 2 or !isWeakKey(args[1])) {
        _ = throwError(env, "TypeError", .{ .string = "Invalid value used in weak set" });
        return .{ .value = .{ .void = {} } };
    }
    if (findIndex(values, args[1]) == null) {
        values.elements.append(env.allocator, args[1]) catch {};
    }
    return .{ .value = args[0] };
}

pub fn WeakSetHas(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const this = getWeakSet(args) orelse return .{ .value = .{ .boolean = false } };
    const values = getValues(this) orelse return .{ .value = .{ .boolean = false } };
    if (args.len < 2) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = findIndex(values, args[1]) != null } };
}

pub fn WeakSetDelete(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const this = getWeakSet(args) orelse return .{ .value = .{ .boolean = false } };
    const values = getValues(this) orelse return .{ .value = .{ .boolean = false } };
    if (args.len < 2) return .{ .value = .{ .boolean = false } };
    const i = findIndex(values, args[1]) orelse return .{ .value = .{ .boolean = false } };
    _ = values.elements.orderedRemove(i);
    return .{ .value = .{ .boolean = true } };
}

const WEAKSET_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "add", .func = WeakSetAdd },
    .{ .name = "has", .func = WeakSetHas },
    .{ .name = "delete", .func = WeakSetDelete },
};

pub const WEAKSET_OBJECT = Types.BuiltinObjectImpl{
    .name = "WeakSet",
    .methods = &WEAKSET_METHODS,
};

const testing = std.testing;

test "WeakSet tracks object membership" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const set = WeakSetConstructor(&.{}, &env).value;
    const key = Ast.ObjectValue.init(allocator) catch return;
    defer key.deinit();

    var add_args = [_]Types.Value{ set, .{ .js_object = key } };
    _ = WeakSetAdd(&add_args, &env);
    var has_args = [_]Types.Value{ set, .{ .js_object = key } };
    try testing.expect(WeakSetHas(&has_args, &env).value.boolean);
    const other = Ast.ObjectValue.init(allocator) catch return;
    defer other.deinit();
    var other_args = [_]Types.Value{ set, .{ .js_object = other } };
    try testing.expect(!WeakSetHas(&other_args, &env).value.boolean);
    var del_args = [_]Types.Value{ set, .{ .js_object = key } };
    _ = WeakSetDelete(&del_args, &env);
    var gone_args = [_]Types.Value{ set, .{ .js_object = key } };
    try testing.expect(!WeakSetHas(&gone_args, &env).value.boolean);
}
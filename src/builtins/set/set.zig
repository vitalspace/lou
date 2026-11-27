const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn getSet(args: []Types.Value) ?Types.Value {
    if (args.len == 0) return null;
    const obj = args[0];
    if (obj != .js_object) return null;
    const t = obj.js_object.properties.get("@@type") orelse return null;
    if (t != .string or !std.mem.eql(u8, t.string, "Set")) return null;
    return obj;
}

fn getValues(obj: Types.Value) ?*Ast.ArrayObject {
    if (obj.js_object.properties.get("values")) |v| {
        if (v == .array) return v.array;
    }
    return null;
}

fn valuesEqual(a: Types.Value, b: Types.Value) bool {
    return switch (a) {
        .integer => |ai| switch (b) {
            .integer => |bi| ai == bi,
            .float => |bf| @as(f64, @floatFromInt(ai)) == bf,
            else => false,
        },
        .float => |af| switch (b) {
            .float => |bf| af == bf,
            .integer => |bi| af == @as(f64, @floatFromInt(bi)),
            else => false,
        },
        .string => |as_| switch (b) {
            .string => |bs| std.mem.eql(u8, as_, bs),
            else => false,
        },
        .boolean => |ab| switch (b) {
            .boolean => |bb| ab == bb,
            else => false,
        },
        .void => b == .void,
        .null => b == .null,
        else => false,
    };
}

pub fn SetConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const obj = Ast.ObjectValue.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };

    const values_arr = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, values_arr) catch {
        values_arr.deinit();
        return .{ .value = .{ .void = {} } };
    };

    obj.properties.put("@@type", .{ .string = "Set" }) catch {};
    obj.properties.put("values", .{ .array = values_arr }) catch {};

    if (args.len >= 1) {
        const source = args[0];
        if (source == .array) {
            for (source.array.elements.items) |elem| {
                var found = false;
                for (values_arr.elements.items) |existing| {
                    if (valuesEqual(existing, elem)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    values_arr.elements.append(env.allocator, elem) catch {};
                }
            }
        } else if (source == .js_object) {
            if (source.js_object.properties.get("length")) |len_val| {
                const len: usize = switch (len_val) {
                    .integer => |n| @intCast(@max(0, n)),
                    .float => |n| @intCast(@max(0, @as(i64, @intFromFloat(n)))),
                    else => 0,
                };
                var buf: [32]u8 = undefined;
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    const key = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                    const elem = source.js_object.properties.get(key) orelse Types.Value{ .void = {} };
                    var found = false;
                    for (values_arr.elements.items) |existing| {
                        if (valuesEqual(existing, elem)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        values_arr.elements.append(env.allocator, elem) catch {};
                    }
                }
            }
        } else if (source == .string) {
            var found = false;
            for (values_arr.elements.items) |existing| {
                if (valuesEqual(existing, source)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                values_arr.elements.append(env.allocator, source) catch {};
            }
        }
    }

    return .{ .value = .{ .js_object = obj } };
}

pub fn SetAdd(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(set_val) orelse return .{ .value = .{ .void = {} } };

    if (args.len > 1) {
        const new_val = args[1];
        var found = false;
        for (values.elements.items) |existing| {
            if (valuesEqual(existing, new_val)) {
                found = true;
                break;
            }
        }
        if (!found) {
            values.elements.append(env.allocator, new_val) catch {};
        }
    }

    return .{ .value = set_val };
}

pub fn SetHas(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .boolean = false } };
    const values = getValues(set_val) orelse return .{ .value = .{ .boolean = false } };

    if (args.len > 1) {
        const search_val = args[1];
        for (values.elements.items) |existing| {
            if (valuesEqual(existing, search_val)) {
                return .{ .value = .{ .boolean = true } };
            }
        }
    }

    return .{ .value = .{ .boolean = false } };
}

pub fn SetDelete(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    const set_val = getSet(args) orelse return .{ .value = .{ .boolean = false } };
    const values = getValues(set_val) orelse return .{ .value = .{ .boolean = false } };

    if (args.len > 1) {
        const search_val = args[1];
        var i: usize = 0;
        while (i < values.elements.items.len) {
            if (valuesEqual(values.elements.items[i], search_val)) {
                _ = values.elements.orderedRemove(i);
                return .{ .value = .{ .boolean = true } };
            }
            i += 1;
        }
    }

    return .{ .value = .{ .boolean = false } };
}

pub fn SetSize(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .integer = 0 } };
    const values = getValues(set_val) orelse return .{ .value = .{ .integer = 0 } };
    return .{ .value = .{ .integer = @intCast(values.elements.items.len) } };
}

pub fn SetClear(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(set_val) orelse return .{ .value = .{ .void = {} } };
    values.elements.clearRetainingCapacity();
    _ = env;
    return .{ .value = set_val };
}

pub fn SetValues(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(set_val) orelse return .{ .value = .{ .void = {} } };

    var iter = Ast.ArrayIterator.initValues(env.allocator, values) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

pub fn SetKeys(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return SetValues(args, env);
}

pub fn SetEntries(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(set_val) orelse return .{ .value = .{ .void = {} } };

    const pairs = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, pairs) catch {
        pairs.deinit();
        return .{ .value = .{ .void = {} } };
    };

    for (values.elements.items) |val| {
        const pair = Ast.ArrayObject.init(env.allocator) catch continue;
        env.arrays.append(env.allocator, pair) catch {
            pair.deinit();
            continue;
        };
        pair.elements.append(env.allocator, val) catch {};
        pair.elements.append(env.allocator, val) catch {};
        pairs.elements.append(env.allocator, .{ .array = pair }) catch {};
    }

    var iter = Ast.ArrayIterator.initValues(env.allocator, pairs) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

pub fn SetForEach(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const set_val = getSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(set_val) orelse return .{ .value = .{ .void = {} } };
    const callback = args[1];
    if (callback != .function and callback != .closure) return .{ .value = .{ .void = {} } };

    const func_node: *Ast.Node = if (callback == .closure)
        @ptrCast(@alignCast(callback.closure.func_node))
    else
        @ptrCast(@alignCast(callback.function));
    const func_params: []const []const u8 = switch (func_node.*) {
        .FunctionDeclaration => |f| f.parameters,
        .ArrowFunction => |f| f.parameters,
        else => &.{},
    };
    const func_body: *Ast.Node = switch (func_node.*) {
        .FunctionDeclaration => |f| f.body,
        .ArrowFunction => |f| f.body,
        else => return .{ .value = .{ .void = {} } },
    };

    var func_env = Environment.initCallable(env.allocator, env, callback) catch {
        return .{ .value = .{ .void = {} } };
    };
    defer func_env.deinit();

    var i: usize = 0;
    while (i < values.elements.items.len) {
        func_env.return_hit = false;
        const val = values.elements.items[i];
        if (func_params.len > 0) func_env.setVar(func_params[0], val) catch {};
        if (func_params.len > 1) func_env.setVar(func_params[1], val) catch {};
        _ = evaluate(func_body, &func_env) catch {};
        if (callbackThrow.propagateThrow(&func_env, env)) return .{ .value = .{ .void = {} } };
        i += 1;
    }

    return .{ .value = .{ .void = {} } };
}

pub fn SetIterator(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return SetValues(args, env);
}

pub fn SetToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .string = "[object Set]" } };
    const values = getValues(set_val) orelse return .{ .value = .{ .string = "[object Set]" } };

    var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch {
        return .{ .value = .{ .string = "[object Set]" } };
    };
    defer buf.deinit(env.allocator);

    buf.appendSlice(env.allocator, "Set(") catch {};
    const str = std.fmt.allocPrint(env.allocator, "{d}", .{values.elements.items.len}) catch {
        return .{ .value = .{ .string = "[object Set]" } };
    };
    buf.appendSlice(env.allocator, str) catch {};
    env.allocator.free(str);
    buf.appendSlice(env.allocator, ")") catch {};

    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "[object Set]" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};

    return .{ .value = .{ .string = result } };
}

const evaluate = @import("../../evaluator.zig").evaluate;
const callbackThrow = @import("../callbacks.zig");

const SET_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "add", .func = SetAdd },
    .{ .name = "has", .func = SetHas },
    .{ .name = "delete", .func = SetDelete },
    .{ .name = "clear", .func = SetClear },
    .{ .name = "values", .func = SetValues },
    .{ .name = "keys", .func = SetKeys },
    .{ .name = "entries", .func = SetEntries },
    .{ .name = "forEach", .func = SetForEach },
    .{ .name = "@@iterator", .func = SetIterator },
    .{ .name = "toString", .func = SetToString },
};

pub const SET_OBJECT = Types.BuiltinObjectImpl{
    .name = "Set",
    .methods = &SET_METHODS,
};

const testing = std.testing;

test "Set constructor creates empty set" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const result = SetConstructor(&.{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .js_object);
    const obj = result.value.js_object;
    try testing.expect(obj.properties.get("@@type") != null);
    try testing.expectEqualSlices(u8, "Set", obj.properties.get("@@type").?.string);
}

test "Set add and has" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const set_val = SetConstructor(&.{}, &env).value;
    var add_args1 = [_]Types.Value{ set_val, .{ .integer = 1 } };
    _ = SetAdd(&add_args1, &env);
    var add_args2 = [_]Types.Value{ set_val, .{ .integer = 2 } };
    _ = SetAdd(&add_args2, &env);
    var add_args3 = [_]Types.Value{ set_val, .{ .integer = 1 } };
    _ = SetAdd(&add_args3, &env); // duplicate

    var has_args1 = [_]Types.Value{ set_val, .{ .integer = 1 } };
    try testing.expect(SetHas(&has_args1, &env).value.boolean);
    var has_args2 = [_]Types.Value{ set_val, .{ .integer = 2 } };
    try testing.expect(SetHas(&has_args2, &env).value.boolean);
    var has_args3 = [_]Types.Value{ set_val, .{ .integer = 3 } };
    try testing.expect(!SetHas(&has_args3, &env).value.boolean);

    var size_args = [_]Types.Value{set_val};
    const size = SetSize(&size_args, &env);
    try testing.expectEqual(@as(i64, 2), size.value.integer);
}

test "Set delete" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const set_val = SetConstructor(&.{}, &env).value;
    var a1 = [_]Types.Value{ set_val, .{ .integer = 1 } };
    _ = SetAdd(&a1, &env);
    var a2 = [_]Types.Value{ set_val, .{ .integer = 2 } };
    _ = SetAdd(&a2, &env);

    var del_args = [_]Types.Value{ set_val, .{ .integer = 1 } };
    const deleted = SetDelete(&del_args, &env);
    try testing.expect(deleted.value.boolean);
    var has_args = [_]Types.Value{ set_val, .{ .integer = 1 } };
    try testing.expect(!SetHas(&has_args, &env).value.boolean);

    var not_del_args = [_]Types.Value{ set_val, .{ .integer = 99 } };
    const not_deleted = SetDelete(&not_del_args, &env);
    try testing.expect(!not_deleted.value.boolean);
}

test "Set from array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const arr = try Ast.ArrayObject.init(allocator);
    env.arrays.append(allocator, arr) catch {};
    try arr.elements.append(allocator, .{ .integer = 1 });
    try arr.elements.append(allocator, .{ .integer = 2 });
    try arr.elements.append(allocator, .{ .integer = 3 });

    var src_args = [_]Types.Value{.{ .array = arr }};
    const set_val = SetConstructor(&src_args, &env).value;
    var size_args = [_]Types.Value{set_val};
    const size = SetSize(&size_args, &env);
    try testing.expectEqual(@as(i64, 3), size.value.integer);
}

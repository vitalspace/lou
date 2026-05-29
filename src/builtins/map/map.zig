const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn getMap(args: []Types.Value) ?Types.Value {
    if (args.len == 0) return null;
    const obj = args[0];
    if (obj != .js_object) return null;
    const t = obj.js_object.properties.get("@@type") orelse return null;
    if (t != .string or !std.mem.eql(u8, t.string, "Map")) return null;
    return obj;
}

fn getEntries(obj: Types.Value) ?*Ast.ArrayObject {
    if (obj.js_object.properties.get("entries")) |v| {
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

fn findEntryIndex(entries: *Ast.ArrayObject, key: Types.Value) ?usize {
    for (entries.elements.items, 0..) |pair, i| {
        if (pair == .array) {
            if (pair.array.elements.items.len >= 1) {
                if (valuesEqual(pair.array.elements.items[0], key)) {
                    return i;
                }
            }
        }
    }
    return null;
}

pub fn MapConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const obj = Ast.ObjectValue.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };

    const entries_arr = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, entries_arr) catch {
        entries_arr.deinit();
        return .{ .value = .{ .void = {} } };
    };

    obj.properties.put("@@type", .{ .string = "Map" }) catch {};
    obj.properties.put("entries", .{ .array = entries_arr }) catch {};

    if (args.len >= 1) {
        const source = args[0];
        if (source == .array) {
            var i: usize = 0;
            while (i < source.array.elements.items.len) : (i += 1) {
                const elem = source.array.elements.items[i];
                if (elem == .array and elem.array.elements.items.len >= 2) {
                    const pair = Ast.ArrayObject.init(env.allocator) catch continue;
                    env.arrays.append(env.allocator, pair) catch {
                        pair.deinit();
                        continue;
                    };
                    pair.elements.append(env.allocator, elem.array.elements.items[0]) catch {};
                    pair.elements.append(env.allocator, elem.array.elements.items[1]) catch {};
                    entries_arr.elements.append(env.allocator, .{ .array = pair }) catch {};
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
                    const key_str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                    const elem = source.js_object.properties.get(key_str) orelse Types.Value{ .void = {} };
                    if (elem == .array and elem.array.elements.items.len >= 2) {
                        const pair = Ast.ArrayObject.init(env.allocator) catch continue;
                        env.arrays.append(env.allocator, pair) catch {
                            pair.deinit();
                            continue;
                        };
                        pair.elements.append(env.allocator, elem.array.elements.items[0]) catch {};
                        pair.elements.append(env.allocator, elem.array.elements.items[1]) catch {};
                        entries_arr.elements.append(env.allocator, .{ .array = pair }) catch {};
                    }
                }
            }
        }
    }

    return .{ .value = .{ .js_object = obj } };
}

pub fn MapSet(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .void = {} } };

    if (args.len >= 3) {
        const key = args[1];
        const value = args[2];

        if (findEntryIndex(entries, key)) |idx| {
            const existing_pair = entries.elements.items[idx];
            if (existing_pair == .array and existing_pair.array.elements.items.len >= 2) {
                existing_pair.array.elements.items[1] = value;
            }
        } else {
            const pair = Ast.ArrayObject.init(env.allocator) catch {
                return .{ .value = map_val };
            };
            env.arrays.append(env.allocator, pair) catch {
                pair.deinit();
                return .{ .value = map_val };
            };
            pair.elements.append(env.allocator, key) catch {};
            pair.elements.append(env.allocator, value) catch {};
            entries.elements.append(env.allocator, .{ .array = pair }) catch {};
        }
    }

    return .{ .value = map_val };
}

pub fn MapGet(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const map_val = getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .void = {} } };

    if (args.len >= 2) {
        const key = args[1];
        if (findEntryIndex(entries, key)) |idx| {
            const pair = entries.elements.items[idx];
            if (pair == .array and pair.array.elements.items.len >= 2) {
                return .{ .value = pair.array.elements.items[1] };
            }
        }
    }

    return .{ .value = .{ .void = {} } };
}

pub fn MapHas(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const map_val = getMap(args) orelse return .{ .value = .{ .boolean = false } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .boolean = false } };

    if (args.len >= 2) {
        const key = args[1];
        if (findEntryIndex(entries, key)) |_| {
            return .{ .value = .{ .boolean = true } };
        }
    }

    return .{ .value = .{ .boolean = false } };
}

pub fn MapDelete(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = getMap(args) orelse return .{ .value = .{ .boolean = false } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .boolean = false } };

    if (args.len >= 2) {
        const key = args[1];
        if (findEntryIndex(entries, key)) |idx| {
            _ = entries.elements.orderedRemove(idx);
            return .{ .value = .{ .boolean = true } };
        }
    }

    _ = env;
    return .{ .value = .{ .boolean = false } };
}

pub fn MapSize(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const map_val = getMap(args) orelse return .{ .value = .{ .integer = 0 } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .integer = 0 } };
    return .{ .value = .{ .integer = @intCast(entries.elements.items.len) } };
}

pub fn MapClear(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .void = {} } };
    entries.elements.clearRetainingCapacity();
    _ = env;
    return .{ .value = map_val };
}

pub fn MapKeys(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .void = {} } };

    const keys_arr = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, keys_arr) catch {
        keys_arr.deinit();
        return .{ .value = .{ .void = {} } };
    };

    for (entries.elements.items) |pair| {
        if (pair == .array and pair.array.elements.items.len >= 1) {
            keys_arr.elements.append(env.allocator, pair.array.elements.items[0]) catch {};
        }
    }

    var iter = Ast.ArrayIterator.initValues(env.allocator, keys_arr) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

pub fn MapValuesMethod(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .void = {} } };

    const vals_arr = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, vals_arr) catch {
        vals_arr.deinit();
        return .{ .value = .{ .void = {} } };
    };

    for (entries.elements.items) |pair| {
        if (pair == .array and pair.array.elements.items.len >= 2) {
            vals_arr.elements.append(env.allocator, pair.array.elements.items[1]) catch {};
        }
    }

    var iter = Ast.ArrayIterator.initValues(env.allocator, vals_arr) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

pub fn MapEntries(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .void = {} } };

    var iter = Ast.ArrayIterator.initValues(env.allocator, entries) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

pub fn MapForEach(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const map_val = getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .void = {} } };
    const callback = args[1];
    if (callback != .function) return .{ .value = .{ .void = {} } };

    const func_node: *Ast.Node = @ptrCast(@alignCast(callback.function));
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

    var func_env = Environment.init(env.allocator, env) catch {
        return .{ .value = .{ .void = {} } };
    };
    defer func_env.deinit();

    var i: usize = 0;
    while (i < entries.elements.items.len) {
        func_env.return_hit = false;
        const pair = entries.elements.items[i];
        if (pair == .array and pair.array.elements.items.len >= 2) {
            const key = pair.array.elements.items[0];
            const val = pair.array.elements.items[1];
            if (func_params.len > 0) func_env.setVar(func_params[0], val) catch {};
            if (func_params.len > 1) func_env.setVar(func_params[1], key) catch {};
            if (func_params.len > 2) func_env.setVar(func_params[2], map_val) catch {};
            _ = evaluate(func_body, &func_env) catch {};
        }
        i += 1;
    }

    return .{ .value = .{ .void = {} } };
}

pub fn MapIterator(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return MapEntries(args, env);
}

pub fn MapToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = getMap(args) orelse return .{ .value = .{ .string = "[object Map]" } };
    const entries = getEntries(map_val) orelse return .{ .value = .{ .string = "[object Map]" } };

    var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch {
        return .{ .value = .{ .string = "[object Map]" } };
    };
    defer buf.deinit(env.allocator);

    buf.appendSlice(env.allocator, "Map(") catch {};
    const str = std.fmt.allocPrint(env.allocator, "{d}", .{entries.elements.items.len}) catch {
        return .{ .value = .{ .string = "[object Map]" } };
    };
    buf.appendSlice(env.allocator, str) catch {};
    env.allocator.free(str);
    buf.appendSlice(env.allocator, ")") catch {};

    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "[object Map]" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};

    return .{ .value = .{ .string = result } };
}

const evaluate = @import("../../evaluator.zig").evaluate;

const MAP_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "set", .func = MapSet },
    .{ .name = "get", .func = MapGet },
    .{ .name = "has", .func = MapHas },
    .{ .name = "delete", .func = MapDelete },
    .{ .name = "size", .func = MapSize },
    .{ .name = "clear", .func = MapClear },
    .{ .name = "keys", .func = MapKeys },
    .{ .name = "values", .func = MapValuesMethod },
    .{ .name = "entries", .func = MapEntries },
    .{ .name = "forEach", .func = MapForEach },
    .{ .name = "@@iterator", .func = MapIterator },
    .{ .name = "toString", .func = MapToString },
};

pub const MAP_OBJECT = Types.BuiltinObjectImpl{
    .name = "Map",
    .methods = &MAP_METHODS,
};

const testing = std.testing;

test "Map constructor creates empty map" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const result = MapConstructor(&.{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .js_object);
    const obj = result.value.js_object;
    try testing.expect(obj.properties.get("@@type") != null);
    try testing.expectEqualSlices(u8, "Map", obj.properties.get("@@type").?.string);
}

test "Map set and get" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const map_val = MapConstructor(&.{}, &env).value;
    var s1 = [_]Types.Value{ map_val, .{ .integer = 1 }, .{ .string = "one" } };
    _ = MapSet(&s1, &env);
    var s2 = [_]Types.Value{ map_val, .{ .integer = 2 }, .{ .string = "two" } };
    _ = MapSet(&s2, &env);

    var g1 = [_]Types.Value{ map_val, .{ .integer = 1 } };
    const v1 = MapGet(&g1, &env);
    try testing.expect(v1.value == .string);
    try testing.expectEqualSlices(u8, "one", v1.value.string);

    var g2 = [_]Types.Value{ map_val, .{ .integer = 2 } };
    const v2 = MapGet(&g2, &env);
    try testing.expect(v2.value == .string);
    try testing.expectEqualSlices(u8, "two", v2.value.string);

    var g3 = [_]Types.Value{ map_val, .{ .integer = 3 } };
    const v3 = MapGet(&g3, &env);
    try testing.expect(v3.value == .void);
}

test "Map has and delete" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const map_val = MapConstructor(&.{}, &env).value;
    var sa = [_]Types.Value{ map_val, .{ .integer = 1 }, .{ .string = "one" } };
    _ = MapSet(&sa, &env);

    var ha1 = [_]Types.Value{ map_val, .{ .integer = 1 } };
    try testing.expect(MapHas(&ha1, &env).value.boolean);
    var ha2 = [_]Types.Value{ map_val, .{ .integer = 2 } };
    try testing.expect(!MapHas(&ha2, &env).value.boolean);

    var da = [_]Types.Value{ map_val, .{ .integer = 1 } };
    const deleted = MapDelete(&da, &env);
    try testing.expect(deleted.value.boolean);
    var ha3 = [_]Types.Value{ map_val, .{ .integer = 1 } };
    try testing.expect(!MapHas(&ha3, &env).value.boolean);
}

test "Map size" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const map_val = MapConstructor(&.{}, &env).value;
    var sz0 = [_]Types.Value{map_val};
    try testing.expectEqual(@as(i64, 0), MapSize(&sz0, &env).value.integer);

    var sb1 = [_]Types.Value{ map_val, .{ .integer = 1 }, .{ .string = "a" } };
    _ = MapSet(&sb1, &env);
    var sb2 = [_]Types.Value{ map_val, .{ .integer = 2 }, .{ .string = "b" } };
    _ = MapSet(&sb2, &env);
    var sz2 = [_]Types.Value{map_val};
    try testing.expectEqual(@as(i64, 2), MapSize(&sz2, &env).value.integer);

    var sb3 = [_]Types.Value{ map_val, .{ .integer = 1 }, .{ .string = "c" } };
    _ = MapSet(&sb3, &env);
    var sz2b = [_]Types.Value{map_val};
    try testing.expectEqual(@as(i64, 2), MapSize(&sz2b, &env).value.integer);
}
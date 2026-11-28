const std = @import("std");
const ast = @import("ast.zig");
const builtinsTypes = @import("./types/types.zig");
const env_mod = @import("environment.zig");
const debugPrint = env_mod.debugPrint;
const optimizations = @import("optimizations.zig");
const GeneratorObject = @import("./types/runtime.zig").GeneratorObject;
const throwError = @import("./builtins/error.zig").throwError;
const coercion = @import("coercion.zig");
const objectPrototypeMod = @import("./builtins/object/prototype.zig");
const booleanMod = @import("./builtins/boolean/boolean.zig");
const functionMod = @import("./builtins/function/function.zig");
const regexpMod = @import("./builtins/regex/regexp.zig");
const promiseMod = @import("./builtins/promise/promise.zig");

pub const Environment = env_mod.Environment;

fn evaluateArgs(args_nodes: []*ast.Node, env: *Environment) anyerror!std.ArrayList(ast.Value) {
    var result = try std.ArrayList(ast.Value).initCapacity(env.allocator, args_nodes.len);
    errdefer result.deinit(env.allocator);

    for (args_nodes) |arg_node| {
        if (arg_node.* == .SpreadExpression) {
            const spread_val = try evaluate(arg_node.SpreadExpression.value, env);
            switch (spread_val) {
                .array => |arr| {
                    for (arr.elements.items) |item| {
                        try result.append(env.allocator, item);
                    }
                },
                .js_object => |obj| {
                    const type_tag = obj.properties.get("@@type");
                    if (type_tag != null and type_tag.? == .string) {
                        if (std.mem.eql(u8, type_tag.?.string, "Set")) {
                            if (obj.properties.get("values")) |vals| {
                                if (vals == .array) {
                                    for (vals.array.elements.items) |item| {
                                        try result.append(env.allocator, item);
                                    }
                                }
                            }
                        } else if (std.mem.eql(u8, type_tag.?.string, "Map")) {
                            if (obj.properties.get("entries")) |ents| {
                                if (ents == .array) {
                                    for (ents.array.elements.items) |item| {
                                        try result.append(env.allocator, item);
                                    }
                                }
                            }
                        }
                    }
                },
                .string => |s| {
                    for (s, 0..) |_, i| {
                        const char_val = s[i..i+1];
                        try result.append(env.allocator, .{ .string = char_val });
                    }
                },
                        .generator => |gen| {
                            while (true) {
                                const next_val = try evaluateGeneratorNext(gen, env);
                                if (next_val != .js_object) break;
                                const done = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                                if (done == .boolean and done.boolean) break;
                                const val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                                try result.append(env.allocator, val);
                            }
                        },
                        .iterator => |it| {
                            while (true) {
                                const next_val = it.next(env.allocator, &env.arrays, &env.objects);
                                if (next_val != .js_object) break;
                                const done = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                                if (done == .boolean and done.boolean) break;
                                const val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                                try result.append(env.allocator, val);
                            }
                        },
                        else => {},
                    }
                } else {
                    const val = try evaluate(arg_node, env);
                    try result.append(env.allocator, val);
                }
            }

            return result;
        }

fn valuesEqual(left: ast.Value, right: ast.Value) bool {
    return switch (left) {
        .integer => |li| switch (right) {
            .integer => |ri| li == ri,
            .float => |rf| @as(f64, @floatFromInt(li)) == rf,
            else => false,
        },
        .float => |ln| switch (right) {
            .float => |rn| ln == rn,
            .integer => |ri| ln == @as(f64, @floatFromInt(ri)),
            else => false,
        },
        .big_int => |lb| switch (right) {
            .big_int => |rb| lb.compare(rb) == .eq,
            else => false,
        },
        .string => |ls| switch (right) {
            .string => |rs| std.mem.eql(u8, ls, rs),
            else => false,
        },
        .boolean => |lb| switch (right) {
            .boolean => |rb| lb == rb,
            else => false,
        },
        .array => |la| switch (right) {
            .array => |ra| la == ra,
            else => false,
        },
        .object => |lo| switch (right) {
            .object => |ro| lo == ro,
            else => false,
        },
        .function => |lf| switch (right) {
            .function => |rf| lf == rf,
            else => false,
        },
        .void => right == .void,
        .null => right == .null,
        .hole => right == .void,
        .array_iterator => |lo| switch (right) {
            .array_iterator => |ro| lo == ro,
            else => false,
        },
        .regexp => |lo| switch (right) {
            .regexp => |ro| lo == ro,
            else => false,
        },
        .closure => |lo| switch (right) {
            .closure => |ro| lo == ro,
            else => false,
        },
        .iterator => |lo| switch (right) {
            .iterator => |ro| lo == ro,
            else => false,
        },
        .js_object => |lo| switch (right) {
            .js_object => |ro| lo == ro,
            else => false,
        },
        .symbol => |ls| switch (right) {
            .symbol => |rs| ls.id == rs.id,
            else => false,
        },
        .generator => |lg| switch (right) {
            .generator => |rg| lg == rg,
            else => false,
        },
    };
}

/// Try to coerce a Number (integer/float) into a `*BigIntValue` when the value
/// is integer-exact and fits in i64. Returns null otherwise (NaN, non-integer,
/// out of range, etc.). Used by loose equality for the BigInt↔Number path.
fn coerceNumberToBigInt(allocator: std.mem.Allocator, bigints_list: *std.ArrayList(*ast.BigIntValue), v: ast.Value) !?*ast.BigIntValue {
    switch (v) {
        .integer => |i| {
            const tmp = ast.BigIntValue.fromString(allocator, "0") catch return null;
            bigints_list.append(allocator, tmp) catch {};
            tmp.value.set(i) catch return null;
            return tmp;
        },
        .float => |f| {
            if (std.math.isNan(f)) return null;
            if (f < @as(f64, @floatFromInt(std.math.minInt(i64))) or f > @as(f64, @floatFromInt(std.math.maxInt(i64)))) return null;
            const i: i64 = @intFromFloat(f);
            if (@as(f64, @floatFromInt(i)) != f) return null; // must be integer-exact
            const tmp = ast.BigIntValue.fromString(allocator, "0") catch return null;
            bigints_list.append(allocator, tmp) catch {};
            tmp.value.set(i) catch return null;
            return tmp;
        },
        else => return null,
    }
}

/// ECMAScript 7.2.14 `IsLooselyEqual(x, y)` — `==` semantics.
///
/// Implements:
/// - same-type → strict comparison (NaN never equal)
/// - null == undefined (and vice-versa)
/// - null/undefined vs anything else → false
/// - String ↔ Number: coerce string to number
/// - BigInt ↔ Number: coerce number to BigInt if integer-exact
/// - BigInt ↔ String: parse string as BigInt (BigInt() rules: no `n`,
///   no `.`, no `e`; failure → false)
/// - Boolean vs anything: coerce boolean to number, then compare
/// - Object → ToPrimitive not implemented yet, returns false
fn looseValuesEqual(
    allocator: std.mem.Allocator,
    bigints_list: *std.ArrayList(*ast.BigIntValue),
    left: ast.Value,
    right: ast.Value,
) bool {
    // Step 1: same type → strict equality.
    if (std.meta.activeTag(left) == std.meta.activeTag(right)) {
        return switch (left) {
            .big_int => |lb| switch (right) {
                .big_int => |rb| lb.compare(rb) == .eq,
                else => unreachable,
            },
            .integer => |li| switch (right) {
                .integer => |ri| li == ri,
                else => unreachable,
            },
            .float => |lf| switch (right) {
                .float => |rf| lf == rf,
                else => unreachable,
            },
            .string => |ls| switch (right) {
                .string => |rs| std.mem.eql(u8, ls, rs),
                else => unreachable,
            },
            .boolean => |lb| switch (right) {
                .boolean => |rb| lb == rb,
                else => unreachable,
            },
            .void => true,
            .null => true,
            .hole => true,
            else => valuesEqual(left, right), // identity for arrays/objects/functions
        };
    }

    // Number <-> Number: integer/float are the same JS Number type.
    if ((left == .integer or left == .float) and (right == .integer or right == .float)) {
        const lf: f64 = if (left == .integer) @floatFromInt(left.integer) else left.float;
        const rf: f64 = if (right == .integer) @floatFromInt(right.integer) else right.float;
        return lf == rf;
    }

    // Step 2/3: null == undefined (and vice-versa).
    if ((left == .null and right == .void) or (left == .void and right == .null)) {
        return true;
    }

    // null/undefined vs anything else → false.
    if (left == .null or left == .void or right == .null or right == .void) {
        return false;
    }

    // Step 4/5: Boolean ↔ anything → coerce boolean to number and recurse.
    // Runs before the BigInt cases: coerceNumberToBigInt rejects booleans,
    // but == coerces them to 0/1 first.
    {
        const bool_side: ?ast.Value = if (left == .boolean) left else if (right == .boolean) right else null;
        if (bool_side != null) {
            const other = if (left == .boolean) right else left;
            const as_num: ast.Value = .{ .integer = if (bool_side.?.boolean) @as(i64, 1) else @as(i64, 0) };
            return looseValuesEqual(allocator, bigints_list, as_num, other);
        }
    }

    // Step 10: Object <-> primitive -> ToPrimitive(default), then recurse.
    {
        const l_obj = coercion.isObjectLike(left);
        const r_obj = coercion.isObjectLike(right);
        if (l_obj != r_obj) {
            const obj_side = if (l_obj) left else right;
            const other = if (l_obj) right else left;
            if (coercion.toPrimitiveString(allocator, obj_side)) |prim| {
                defer allocator.free(prim);
                return looseValuesEqual(allocator, bigints_list, .{ .string = prim }, other);
            }
        }
    }

    // Step 6: BigInt ↔ String → StringToBigInt (integer literal syntax only;
    // "1.0", "1e2" or "1n" parse to no value and compare false).
    {
        const big_side: ?ast.Value = if (left == .big_int) left else if (right == .big_int) right else null;
        const str_side: ?ast.Value = if (left == .string) left else if (right == .string) right else null;
        if (big_side != null and str_side != null) {
            const parsed = ast.BigIntValue.fromString(allocator, str_side.?.string) catch return false;
            bigints_list.append(allocator, parsed) catch {};
            return big_side.?.big_int.compare(parsed) == .eq;
        }
    }

    // Step 7: Number (integer/float) ↔ String → coerce string to number.
    {
        const str_side: ?ast.Value = if (left == .string) left else if (right == .string) right else null;
        if (str_side != null) {
            const num_side = if (left == .string) right else left;
            const parsed = coercion.stringToNumber(str_side.?.string);
            return switch (num_side) {
                .integer => |i| parsed == @as(f64, @floatFromInt(i)),
                .float => |f| parsed == f,
                else => false,
            };
        }
    }

    // Step 8: BigInt ↔ Number → coerce number to BigInt if integer-exact.
    {
        const big_side: ?ast.Value = if (left == .big_int) left else if (right == .big_int) right else null;
        if (big_side != null) {
            const num_side = if (left == .big_int) right else left;
            if (num_side != .integer and num_side != .float) return false;
            const coerced = coerceNumberToBigInt(allocator, bigints_list, num_side) catch return false;
            const other = coerced orelse return false;
            return big_side.?.big_int.compare(other) == .eq;
        }
    }

    // Step 11/12: Object ↔ primitive → ToPrimitive not implemented, return false.
    return false;
}

fn consumeBreak(env: *Environment, my_label: ?[]const u8) void {
    if (!env.break_hit) return;
    if (env.break_label == null or (my_label != null and std.mem.eql(u8, env.break_label.?, my_label.?))) {
        env.break_hit = false;
        env.break_label = null;
    }
}

fn consumeContinue(env: *Environment, my_label: ?[]const u8) bool {
    // Returns true if the continue was consumed (label matched or unlabeled)
    if (!env.continue_hit) return false;
    if (env.continue_label == null or (my_label != null and std.mem.eql(u8, env.continue_label.?, my_label.?))) {
        env.continue_hit = false;
        env.continue_label = null;
        return true;
    }
    return false;
}

fn valueToF64(v: ast.Value) !f64 {
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        .boolean => |b| if (b) 1.0 else 0.0,
        .string => |s| std.fmt.parseFloat(f64, s) catch 0.0,
        .void => 0.0,
        else => error.TypeMismatch,
    };
}

/// Append one value using JS string coercion (used by `+=`).
fn appendValueString(env: *Environment, buf: *std.ArrayList(u8), v: ast.Value) !void {
    switch (v) {
        .string => |s| try buf.appendSlice(env.allocator, s),
        .big_int => |bi| {
            const digits = try bi.toString(env.allocator);
            defer env.allocator.free(digits);
            try buf.appendSlice(env.allocator, digits);
        },
        .integer => |i| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return error.OutOfMemory;
            try buf.appendSlice(env.allocator, s);
        },
        .float => |f| {
            var tmp: [64]u8 = undefined;
            const s = if (std.math.isNan(f)) "NaN" else std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return error.OutOfMemory;
            try buf.appendSlice(env.allocator, s);
        },
        .boolean => |bl| try buf.appendSlice(env.allocator, if (bl) "true" else "false"),
        .void => try buf.appendSlice(env.allocator, "undefined"),
        else => try buf.appendSlice(env.allocator, "[object]"),
    }
}

/// Property key coercion for computed member access (`obj[expr]`).
fn valueToKeyString(env: *Environment, key: ast.Value) ![]const u8 {
    switch (key) {
        .string => |s| return s,
        .integer => |i| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return error.OutOfMemory;
            const owned = try env.allocator.dupe(u8, s);
            env.owned_strings.append(env.allocator, owned) catch {};
            return owned;
        },
        .float => |f| {
            var tmp: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return error.OutOfMemory;
            const owned = try env.allocator.dupe(u8, s);
            env.owned_strings.append(env.allocator, owned) catch {};
            return owned;
        },
        .boolean => |bl| return if (bl) "true" else "false",
        else => return error.InvalidIndex,
    }
}

fn keyToArrayIndex(key: ast.Value) ?usize {
    return switch (key) {
        .integer => |i| if (i < 0) null else @intCast(i),
        .float => |f| if (std.math.isNan(f) or f < 0.0) null else @intFromFloat(f),
        .big_int => |b| blk: {
            const i = b.toI64() orelse break :blk null;
            if (i < 0) break :blk null;
            break :blk @intCast(i);
        },
        else => null,
    };
}

fn readIndexed(env: *Environment, obj_val: ast.Value, key_val: ast.Value) !ast.Value {
    if (obj_val == .js_object) {
        const key = try valueToKeyString(env, key_val);
        return obj_val.js_object.properties.get(key) orelse .{ .void = {} };
    }
    if (obj_val == .array) {
        const index = keyToArrayIndex(key_val) orelse return .{ .void = {} };
        const value = obj_val.array.get(index) orelse return .{ .void = {} };
        return if (value == .hole) .{ .void = {} } else value;
    }
    return error.InvalidAssignment;
}

fn writeIndexed(env: *Environment, obj_val: ast.Value, key_val: ast.Value, val: ast.Value) !void {
    if (obj_val == .js_object) {
        const key = try valueToKeyString(env, key_val);
        try obj_val.js_object.properties.put(key, val);
        return;
    }
    if (obj_val == .array) {
        const index = keyToArrayIndex(key_val) orelse return;
        try obj_val.array.set(index, val);
        return;
    }
    return error.InvalidAssignment;
}

pub fn evaluate(node: *ast.Node, env: *Environment) !ast.Value {
    const setLoopVar = struct {
        fn set(scope: *Environment, kind: ast.ForOfKind, name: []const u8, val: ast.Value) !void {
            switch (kind) {
                .Const => {
                    try scope.values.put(name, val);
                    if (!scope.constants.contains(name)) {
                        try scope.constants.put(name, {});
                    }
                },
                .Let => {
                    try scope.values.put(name, val);
                },
                .Var => {
                    try scope.setVar(name, val);
                },
            }
        }
    }.set;

    switch (node.*) {
        .IntegerLiteral => |i| return .{ .integer = i.value },
        .FloatLiteral => |f| return .{ .float = f.value },
        .BigIntLiteral => |b| {
            const big = ast.BigIntValue.fromString(env.allocator, b.value) catch return .{ .void = {} };
            env.bigints.append(env.allocator, big) catch {};
            return .{ .big_int = big };
        },
        .StringLiteral => |s| return .{ .string = s.value },
        .BooleanLiteral => |b| return .{ .boolean = b.value },
        .NullLiteral => return .{ .null = {} },
        .VoidLiteral => return .{ .void = {} },
        .ArrayLiteral => |a| {
            const array_obj = try ast.ArrayObject.init(env.allocator);
            errdefer array_obj.deinit();

            for (a.elements) |elem| {
                if (elem.* == .SpreadExpression) {
                    const spread_val = try evaluate(elem.SpreadExpression.value, env);
                    switch (spread_val) {
                        .array => |src_arr| {
                            for (src_arr.elements.items) |item| {
                                // Spread reads holes as undefined (ArrayIterator), so the
                                // new array gets dense undefined values, not new holes.
                                const value: ast.Value = if (item == .hole) .{ .void = {} } else item;
                                try array_obj.elements.append(env.allocator, value);
                            }
                        },
                        .js_object => |obj| {
                            const type_tag = obj.properties.get("@@type");
                            if (type_tag != null and type_tag.? == .string) {
                                if (std.mem.eql(u8, type_tag.?.string, "Set")) {
                                    if (obj.properties.get("values")) |vals| {
                                        if (vals == .array) {
                                            for (vals.array.elements.items) |item| {
                                                try array_obj.elements.append(env.allocator, item);
                                            }
                                        }
                                    }
                                } else if (std.mem.eql(u8, type_tag.?.string, "Map")) {
                                    if (obj.properties.get("entries")) |ents| {
                                        if (ents == .array) {
                                            for (ents.array.elements.items) |item| {
                                                try array_obj.elements.append(env.allocator, item);
                                            }
                                        }
                                    }
                                }
                            }
                        },
                        .string => |s| {
                            for (s, 0..) |_, i| {
                                const char_val = s[i..i+1];
                                try array_obj.elements.append(env.allocator, .{ .string = char_val });
                            }
                        },
                        .generator => |gen| {
                            while (true) {
                                const next_val = try evaluateGeneratorNext(gen, env);
                                if (next_val != .js_object) break;
                                const done = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                                if (done == .boolean and done.boolean) break;
                                const val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                                try array_obj.elements.append(env.allocator, val);
                            }
                        },
                        .iterator => |it| {
                            while (true) {
                                const next_val = it.next(env.allocator, &env.arrays, &env.objects);
                                if (next_val != .js_object) break;
                                const done = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                                if (done == .boolean and done.boolean) break;
                                const val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                                try array_obj.elements.append(env.allocator, val);
                            }
                        },
                        else => {},
                    }
                } else if (elem.* == .Elision) {
                    try array_obj.elements.append(env.allocator, .{ .hole = {} });
                } else {
                    const val = try evaluate(elem, env);
                    try array_obj.elements.append(env.allocator, val);
                }
            }

            try env.arrays.append(env.allocator, array_obj);

            return .{ .array = array_obj };
        },
        .ObjectLiteral => |o| {
            const obj = try ast.ObjectValue.init(env.allocator);
            errdefer obj.deinit();
            obj.prototype = env.object_prototype;

            for (o.properties) |prop| {
                if (prop.value.* == .SpreadExpression) {
                    const spread_val = try evaluate(prop.value.SpreadExpression.value, env);
                    if (spread_val == .js_object) {
                        var it = spread_val.js_object.properties.iterator();
                        while (it.next()) |entry| {
                            // Skip internal @@type keys, copy all others
                            if (entry.key_ptr.*.len > 2 and std.mem.eql(u8, entry.key_ptr.*[0..2], "@@")) continue;
                            try obj.properties.put(entry.key_ptr.*, entry.value_ptr.*);
                        }
                    }
                } else {
                    const val = try evaluate(prop.value, env);
                    const key = if (prop.key_expr) |ke| blk: {
                        const key_val = try evaluate(ke, env);
                        break :blk switch (key_val) {
                            .string => |s| s,
                            .integer => |i| blk2: {
                                var buf: [32]u8 = undefined;
                                const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                                const owned = try env.allocator.dupe(u8, s);
                                env.owned_strings.append(env.allocator, owned) catch {};
                                break :blk2 owned;
                            },
                            .float => |f| blk2: {
                                var buf: [64]u8 = undefined;
                                const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.OutOfMemory;
                                const owned = try env.allocator.dupe(u8, s);
                                env.owned_strings.append(env.allocator, owned) catch {};
                                break :blk2 owned;
                            },
                            .boolean => |b| if (b) "true" else "false",
                            .null => "null",
                            .void => "undefined",
                            .symbol => |sym| blk2: {
                                const prop_name = try ast.symbolPropertyName(env.allocator, sym.description);
                                env.owned_strings.append(env.allocator, prop_name) catch {};
                                break :blk2 prop_name;
                            },
                            else => "[object Object]",
                        };
                    } else prop.key;
                    if (prop.kind == .init) {
                        try obj.properties.put(key, val);
                    } else {
                        var accessor: *ast.ObjectValue = undefined;
                        if (obj.properties.get(key)) |existing| {
                            if (isAccessorValue(existing)) {
                                accessor = existing.js_object;
                            } else {
                                accessor = try ast.ObjectValue.init(env.allocator);
                                try env.objects.append(env.allocator, accessor);
                                try accessor.properties.put("@@native", .{ .string = "Accessor" });
                            }
                        } else {
                            accessor = try ast.ObjectValue.init(env.allocator);
                            try env.objects.append(env.allocator, accessor);
                            try accessor.properties.put("@@native", .{ .string = "Accessor" });
                        }
                        try accessor.properties.put(if (prop.kind == .get) "get" else "set", val);
                        try obj.properties.put(key, .{ .js_object = accessor });
                    }
                }
            }

            try env.objects.append(env.allocator, obj);
            return .{ .js_object = obj };
        },
        .ArrayIndex => |a| {
            const array_val = try evaluate(a.array, env);
            if (array_val == .iterator) {
                return .{ .void = {} };
            }
            if (array_val == .generator) {
                const index_val = try evaluate(a.index, env);
                if (index_val == .symbol) {
                    const prop_name = try ast.symbolPropertyName(env.allocator, index_val.symbol.description);
                    env.owned_strings.append(env.allocator, prop_name) catch {};
                    if (std.mem.eql(u8, prop_name, "@@iterator")) {
                        return array_val;
                    }
                }
                return .{ .void = {} };
            }
            if (array_val == .js_object) {
                const index_val = try evaluate(a.index, env);
                const key = switch (index_val) {
                    .string => |s| s,
                    .integer => |i| blk: {
                        var buf: [32]u8 = undefined;
                        const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                        const owned = try env.allocator.dupe(u8, s);
                        env.owned_strings.append(env.allocator, owned) catch {};
                        break :blk owned;
                    },
                    .float => |f| blk: {
                        var buf: [64]u8 = undefined;
                        const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.OutOfMemory;
                        const owned = try env.allocator.dupe(u8, s);
                        env.owned_strings.append(env.allocator, owned) catch {};
                        break :blk owned;
                    },
                    .symbol => |sym| blk: {
                        const prop_name = try ast.symbolPropertyName(env.allocator, sym.description);
                        env.owned_strings.append(env.allocator, prop_name) catch {};
                        break :blk prop_name;
                    },
                    else => return error.InvalidIndex,
                };
                var cur: ?*ast.ObjectValue = array_val.js_object;
                while (cur) |o| {
                    if (o.properties.get(key)) |v| {
                        if (accessorPart(v, "get")) |getter| {
                            return try callFunctionValue(getter, &[_]ast.Value{}, env, .{ .js_object = array_val.js_object });
                        }
                        if (isAccessorValue(v)) return .{ .void = {} };
                        return v;
                    }
                    cur = o.prototype;
                }
                return .{ .void = {} };
            }
            if (array_val != .array) {
                return error.NotAnArray;
            }
            const index_val = try evaluate(a.index, env);
            const key_str: ?[]const u8 = switch (index_val) {
                .symbol => |sym| blk: {
                    const prop_name = try ast.symbolPropertyName(env.allocator, sym.description);
                    env.owned_strings.append(env.allocator, prop_name) catch {};
                    break :blk prop_name;
                },
                else => null,
            };

            if (key_str) |k| {
                if (array_val.array.extras) |extras| {
                    if (extras.properties.get(k)) |v| {
                        return v;
                    }
                }
                if (std.mem.eql(u8, k, "@@iterator")) {
                    const iter = try ast.ArrayIterator.initValues(env.allocator, array_val.array);
                    try env.iterators.append(env.allocator, iter);
                    return .{ .iterator = iter };
                }
                return .{ .void = {} };
            }

            const index: usize = switch (index_val) {
                .integer => |i| if (i < 0) return .{ .void = {} } else @intCast(i),
                .float => |f| blk: {
                    if (std.math.isNan(f) or f < 0.0) return .{ .void = {} };
                    break :blk @as(usize, @intFromFloat(f));
                },
                .big_int => |b| blk: {
                    // Per ES2020: BigInt out-of-range / negative index returns undefined.
                    const i = b.toI64() orelse return .{ .void = {} };
                    if (i < 0) return .{ .void = {} };
                    break :blk @as(usize, @intCast(i));
                },
                else => return error.InvalidIndex,
            };
            if (array_val.array.get(index)) |value| {
                if (value == .hole) return .{ .void = {} };
                return value;
            } else {
                return .{ .void = {} };
            }
        },
        .PropertySet => |p| {
            const object_val = try evaluate(p.object, env);
            if (object_val != .js_object) {
                return error.InvalidAssignmentTarget;
            }
            const val = try evaluate(p.value, env);
            if (!try setAccessorProperty(env, object_val.js_object, p.key, val)) {
                try object_val.js_object.properties.put(p.key, val);
            }
            if (env.globalObject()) |g| {
                if (g == object_val.js_object) env.setGlobalProperty(p.key, val);
            }
            return val;
        },
        .Identifier => |i| {
            if (env.getFunction(i.name)) |funcNode| {
                return .{ .function = @ptrCast(funcNode) };
            } else if (env.get(i.name)) |value| {
                if (value == .hole) {
                    _ = throwTdzValue(env, i.name);
                    return error.Thrown;
                }
                return value;
            } else if (env.getBuiltinObject(i.name)) |obj| {
                return .{ .object = @ptrCast(obj) };
            } else if (env.globalObject()) |g| {
                if (g.properties.get(i.name)) |v| return v;
                return error.UndefinedVariable;
            } else {
                return error.UndefinedVariable;
            }
        },
        .BinaryExpression => |b| {
            if (b.operator == .Assign) {
                if (b.left.* == .MemberAccess) {
                    const obj_val = try evaluate(b.left.MemberAccess.object, env);
                    if (obj_val == .regexp) {
                        const val = try evaluate(b.right, env);
                        regexpMod.setProperty(obj_val.regexp, b.left.MemberAccess.property, val) catch {};
                        return val;
                    }
                    if (obj_val != .js_object) return error.InvalidAssignment;
                    const val = try evaluate(b.right, env);
                    if (!try setAccessorProperty(env, obj_val.js_object, b.left.MemberAccess.property, val)) {
                        try obj_val.js_object.properties.put(b.left.MemberAccess.property, val);
                    }
                    if (env.globalObject()) |g| {
                        if (g == obj_val.js_object) env.setGlobalProperty(b.left.MemberAccess.property, val);
                    }
                    return val;
                }
                if (b.left.* == .ArrayIndex) {
                    const ai = b.left.ArrayIndex;
                    const obj_val = try evaluate(ai.array, env);
                    const val = try evaluate(b.right, env);
                    if (obj_val == .js_object) {
                        const key_val = try evaluate(ai.index, env);
                        const key: []const u8 = switch (key_val) {
                            .string => |s| s,
                            .integer => |i| blk: {
                                var buf: [32]u8 = undefined;
                                const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                                const owned = try env.allocator.dupe(u8, s);
                                env.owned_strings.append(env.allocator, owned) catch {};
                                break :blk owned;
                            },
                            .float => |f| blk: {
                                var buf: [64]u8 = undefined;
                                const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.OutOfMemory;
                                const owned = try env.allocator.dupe(u8, s);
                                env.owned_strings.append(env.allocator, owned) catch {};
                                break :blk owned;
                            },
                            else => return error.InvalidIndex,
                        };
                        if (!try setAccessorProperty(env, obj_val.js_object, key, val)) {
                            try obj_val.js_object.properties.put(key, val);
                        }
                        if (env.globalObject()) |g| {
                            if (g == obj_val.js_object) env.setGlobalProperty(key, val);
                        }
                        return val;
                    }
                    if (obj_val == .array) {
                        // Evaluate the index now so BigInt/Integer/Float are handled.
                        const key_val = try evaluate(ai.index, env);
                        const index: usize = switch (key_val) {
                            .integer => |i| if (i < 0) return val else @intCast(i),
                            .float => |f| blk: {
                                if (f < 0.0 or std.math.isNan(f)) return val;
                                break :blk @as(usize, @intFromFloat(f));
                            },
                            .big_int => |big| blk: {
                                // Per ES2020: BigInt index out of range / negative -> assignment is a no-op (extends).
                                const i = big.toI64() orelse return val;
                                if (i < 0) return val;
                                break :blk @as(usize, @intCast(i));
                            },
                            else => return val,
                        };
                        try obj_val.array.set(index, val);
                        return val;
                    }
                    return error.InvalidAssignment;
                }
                if (b.left.* != .Identifier) {
                    return error.InvalidAssignment;
                }
                const name = b.left.Identifier.name;
                const value = try evaluate(b.right, env);
                try env.setInScope(name, value);
                return value;
            }

            if (b.operator == .PlusAssign or b.operator == .MinusAssign or
                b.operator == .MultiplyAssign or b.operator == .DivideAssign or
                b.operator == .ModuloAssign or b.operator == .UnsignedRightShiftAssign or
                b.operator == .LeftShiftAssign or b.operator == .RightShiftAssign)
            {
                const target = b.left.*;
                const name = if (target == .Identifier) target.Identifier.name else "";
                var obj_val: ast.Value = .{ .void = {} };
                var key_val: ast.Value = .{ .void = {} };
                const current_val: ast.Value = switch (target) {
                    .Identifier => env.get(name) orelse return error.UndefinedVariable,
                    .MemberAccess => |m| blk: {
                        obj_val = try evaluate(m.object, env);
                        if (obj_val != .js_object) return error.InvalidAssignment;
                        break :blk obj_val.js_object.properties.get(m.property) orelse ast.Value{ .void = {} };
                    },
                    .ArrayIndex => |ai| blk: {
                        obj_val = try evaluate(ai.array, env);
                        key_val = try evaluate(ai.index, env);
                        break :blk try readIndexed(env, obj_val, key_val);
                    },
                    else => return error.InvalidAssignment,
                };
                const right_val = try evaluate(b.right, env);
                const result: ast.Value = if (b.operator == .PlusAssign and
                    (current_val == .string or right_val == .string)) blk: {
                    var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch return error.OutOfMemory;
                    defer buf.deinit(env.allocator);
                    try appendValueString(env, &buf, current_val);
                    try appendValueString(env, &buf, right_val);
                    const s = buf.toOwnedSlice(env.allocator) catch return error.OutOfMemory;
                    env.owned_strings.append(env.allocator, s) catch {};
                    break :blk .{ .string = s };
                } else switch (b.operator) {
                    .PlusAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .integer = lv + rv },
                            .float => |rv| ast.Value{ .float = @as(f64, @floatFromInt(lv)) + rv },
                            else => return error.TypeMismatch,
                        },
                        .float => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = lv + @as(f64, @floatFromInt(rv)) },
                            .float => |rv| ast.Value{ .float = lv + rv },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .MinusAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .integer = lv - rv },
                            .float => |rv| ast.Value{ .float = @as(f64, @floatFromInt(lv)) - rv },
                            else => return error.TypeMismatch,
                        },
                        .float => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = lv - @as(f64, @floatFromInt(rv)) },
                            .float => |rv| ast.Value{ .float = lv - rv },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .MultiplyAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .integer = lv * rv },
                            .float => |rv| ast.Value{ .float = @as(f64, @floatFromInt(lv)) * rv },
                            else => return error.TypeMismatch,
                        },
                        .float => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = lv * @as(f64, @floatFromInt(rv)) },
                            .float => |rv| ast.Value{ .float = lv * rv },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .DivideAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = @as(f64, @floatFromInt(lv)) / @as(f64, @floatFromInt(rv)) },
                            .float => |rv| ast.Value{ .float = @as(f64, @floatFromInt(lv)) / rv },
                            else => return error.TypeMismatch,
                        },
                        .float => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = lv / @as(f64, @floatFromInt(rv)) },
                            .float => |rv| ast.Value{ .float = lv / rv },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .ModuloAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .integer = @mod(lv, rv) },
                            .float => |rv| ast.Value{ .float = @mod(@as(f64, @floatFromInt(lv)), rv) },
                            else => return error.TypeMismatch,
                        },
                        .float => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = @mod(lv, @as(f64, @floatFromInt(rv))) },
                            .float => |rv| ast.Value{ .float = @mod(lv, rv) },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .PowerAssign => .{ .float = std.math.pow(f64, try valueToF64(current_val), try valueToF64(right_val)) },
                    .UnsignedRightShiftAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{
                                .integer = @as(i64, @as(u32, @bitCast(@as(i32, @truncate(lv)))) >> @as(u5, @intCast(rv & 0x1f))),
                            },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .LeftShiftAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .integer = lv << @intCast(rv) },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .RightShiftAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .integer = lv >> @intCast(rv) },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    else => unreachable,
                };
                switch (target) {
                    .Identifier => try env.setInScope(name, result),
                    .MemberAccess => |m| try obj_val.js_object.properties.put(m.property, result),
                    .ArrayIndex => try writeIndexed(env, obj_val, key_val, result),
                    else => unreachable,
                }
                return result;
            }

            if (b.operator == .Not) {
                const val = try evaluate(b.right, env);
                const result = switch (val) {
                    .boolean => |bv| !bv,
                    .integer => |iv| iv == 0,
                    .float => |fv| fv == 0.0,
                    .string => |sv| sv.len == 0,
                    .void => true,
                    else => false,
                };
                return .{ .boolean = result };
            }

            if (b.operator == .BitNot) {
                const val = try evaluate(b.right, env);
                return switch (val) {
                    .integer => |iv| .{ .integer = ~iv },
                    .float => |fv| .{ .integer = ~@as(i64, @intFromFloat(fv)) },
                    else => return error.TypeMismatch,
                };
            }

            if (b.operator == .Nullish) {
                const left = try evaluate(b.left, env);
                return switch (left) {
                    .void, .null => try evaluate(b.right, env),
                    else => left,
                };
            }

            // Logical assignment: &&=, ||=, ??= with short-circuit semantics.
            if (b.operator == .AndAssign or b.operator == .OrAssign or b.operator == .NullishAssign) {
                const current = try evaluate(b.left, env);
                const should_assign = switch (b.operator) {
                    .AndAssign => switch (current) {
                        .boolean => |v| v,
                        .integer => |v| v != 0,
                        .float => |v| v != 0.0 and !std.math.isNan(v),
                        .string => |v| v.len > 0,
                        else => current != .void and current != .null,
                    },
                    .OrAssign => switch (current) {
                        .boolean => |v| !v,
                        .integer => |v| v == 0,
                        .float => |v| v == 0.0 or std.math.isNan(v),
                        .string => |v| v.len == 0,
                        else => current == .void or current == .null,
                    },
                    .NullishAssign => current == .void or current == .null,
                    else => unreachable,
                };
                if (should_assign) {
                    const val = try evaluate(b.right, env);
                    // Set the value on the LHS target (Identifier, MemberAccess, or ArrayIndex)
                    switch (b.left.*) {
                        .Identifier => |ident| {
                            try env.setInScope(ident.name, val);
                        },
                        .MemberAccess => |m| {
                            const obj_val = try evaluate(m.object, env);
                            if (obj_val == .js_object) {
                                try obj_val.js_object.properties.put(m.property, val);
                            } else return error.InvalidAssignment;
                        },
                        .ArrayIndex => |ai| {
                            const obj_val = try evaluate(ai.array, env);
                            const idx_val = try evaluate(ai.index, env);
                            if (obj_val == .array) {
                                const index = switch (idx_val) {
                                    .integer => |i| if (i >= 0) @as(usize, @intCast(i)) else return error.InvalidAssignmentTarget,
                                    else => return error.InvalidAssignmentTarget,
                                };
                                try obj_val.array.set(index, val);
                            } else if (obj_val == .js_object) {
                                const key: []const u8 = switch (idx_val) {
                                    .string => |s| s,
                                    .integer => |i| blk: {
                                        var buf: [32]u8 = undefined;
                                        const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                                        const owned = try env.allocator.dupe(u8, s);
                                        env.owned_strings.append(env.allocator, owned) catch {};
                                        break :blk owned;
                                    },
                                    else => return error.InvalidIndex,
                                };
                                try obj_val.js_object.properties.put(key, val);
                            } else return error.InvalidAssignment;
                        },
                        else => return error.InvalidAssignmentTarget,
                    }
                    return val;
                }
                return current;
            }

            if (b.operator == .Pipe) {
                const left_val = try evaluate(b.left, env);
                switch (b.right.*) {
                    .Identifier => |ident| {
                        if (env.getBuiltin(ident.name)) |builtin_fn| {
                            var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                            defer args.deinit(env.allocator);
                            try args.append(env.allocator, left_val);
                            const result = builtin_fn(args.items, env);
                            if (env.throw_hit) return error.Thrown;
                            return switch (result) {
                                .value => |val| val,
                                .void => .{ .float = 0.0 },
                            };
                        }
                        const func_node = env.getFunction(ident.name) orelse return error.UndefinedFunction;
                        var pipe_ident_args = [_]ast.Value{left_val};
                        return try invokeFunctionNode(func_node, &pipe_ident_args, env, .{ .void = {} });
                    },
                    .FunctionCall => |fc| {
                        var func_env = try Environment.init(env.allocator, env);
                        defer func_env.deinit();
                        const func_node = env.getFunction(fc.name) orelse {
                            if (env.getBuiltin(fc.name)) |builtin_fn| {
                                var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                                defer args.deinit(env.allocator);
                                try args.append(env.allocator, left_val);
                                for (fc.arguments) |arg| {
                                    const val = try evaluate(arg, env);
                                    try args.append(env.allocator, val);
                                }
                                const result = builtin_fn(args.items, env);
                                if (env.throw_hit) return error.Thrown;
                                return switch (result) {
                                    .value => |val| val,
                                    .void => .{ .float = 0.0 },
                                };
                            }
                            return error.UndefinedFunction;
                        };

                        var pipe_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 1 + fc.arguments.len);
                        defer pipe_args.deinit(env.allocator);
                        try pipe_args.append(env.allocator, left_val);
                        for (fc.arguments) |arg| {
                            try pipe_args.append(env.allocator, try evaluate(arg, env));
                        }
                        return try invokeFunctionNode(func_node, pipe_args.items, env, .{ .void = {} });
                    },
                    else => return error.InvalidPipeline,
                }
            }

            if (b.operator == .Equal or b.operator == .NotEqual or
                b.operator == .StrictEqual or b.operator == .StrictNotEqual)
            {
                const left = try evaluate(b.left, env);
                const right = try evaluate(b.right, env);
                const result = switch (b.operator) {
                    .StrictEqual => valuesEqual(left, right),
                    .StrictNotEqual => !valuesEqual(left, right),
                    .Equal => looseValuesEqual(env.allocator, &env.bigints, left, right),
                    .NotEqual => !looseValuesEqual(env.allocator, &env.bigints, left, right),
                    else => unreachable,
                };
                return .{ .boolean = result };
            }

            if (b.operator == .And or b.operator == .Or) {
                const left = try evaluate(b.left, env);
                const left_truthy = switch (left) {
                    .boolean => |bv| bv,
                    .integer => |iv| iv != 0,
                    .float => |fv| fv != 0.0,
                    .big_int => |big| !big.value.eqlZero(),
                    .string => |sv| sv.len > 0,
                    .void, .null => false,
                    else => true,
                };

                if (b.operator == .And) {
                    if (!left_truthy) return left;
                    return try evaluate(b.right, env);
                } else {
                    if (left_truthy) return left;
                    return try evaluate(b.right, env);
                }
            }

            const left = try evaluate(b.left, env);
            const right = try evaluate(b.right, env);

            if (b.operator == .Plus and (left == .string or right == .string)) {
                var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch return error.OutOfMemory;
                defer buf.deinit(env.allocator);
                switch (left) {
                    .string => |s| buf.appendSlice(env.allocator, s) catch return error.OutOfMemory,
                    .big_int => |bi| {
                        const digits = bi.toString(env.allocator) catch return error.OutOfMemory;
                        defer env.allocator.free(digits);
                        buf.appendSlice(env.allocator, digits) catch return error.OutOfMemory;
                    },
                    .integer => |i| {
                        var tmp: [32]u8 = undefined;
                        const written = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return error.OutOfMemory;
                        buf.appendSlice(env.allocator, written) catch return error.OutOfMemory;
                    },
                    .float => |f| {
                        const s = if (std.math.isNan(f)) "NaN" else blk: {
                            var tmp: [64]u8 = undefined;
                            break :blk std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return error.OutOfMemory;
                        };
                        buf.appendSlice(env.allocator, s) catch return error.OutOfMemory;
                    },
                    .boolean => |bl| {
                        const s = if (bl) "true" else "false";
                        buf.appendSlice(env.allocator, s) catch return error.OutOfMemory;
                    },
                    .void => buf.appendSlice(env.allocator, "undefined") catch return error.OutOfMemory,
                    else => buf.appendSlice(env.allocator, "[object]") catch return error.OutOfMemory,
                }
                switch (right) {
                    .string => |s| buf.appendSlice(env.allocator, s) catch return error.OutOfMemory,
                    .big_int => |bi| {
                        const digits = bi.toString(env.allocator) catch return error.OutOfMemory;
                        defer env.allocator.free(digits);
                        buf.appendSlice(env.allocator, digits) catch return error.OutOfMemory;
                    },
                    .integer => |i| {
                        var tmp: [32]u8 = undefined;
                        const written = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return error.OutOfMemory;
                        buf.appendSlice(env.allocator, written) catch return error.OutOfMemory;
                    },
                    .float => |f| {
                        const s = if (std.math.isNan(f)) "NaN" else blk: {
                            var tmp: [64]u8 = undefined;
                            break :blk std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return error.OutOfMemory;
                        };
                        buf.appendSlice(env.allocator, s) catch return error.OutOfMemory;
                    },
                    .boolean => |bl| {
                        const s = if (bl) "true" else "false";
                        buf.appendSlice(env.allocator, s) catch return error.OutOfMemory;
                    },
                    .void => buf.appendSlice(env.allocator, "undefined") catch return error.OutOfMemory,
                    else => buf.appendSlice(env.allocator, "[object]") catch return error.OutOfMemory,
                }
                const owned = buf.toOwnedSlice(env.allocator) catch return error.OutOfMemory;
                env.owned_strings.append(env.allocator, owned) catch {};
                return .{ .string = owned };
            }

            if (b.operator == .In) {
                // ECMAScript 12.9.3: check if `left` is a property of `right`.
                // The left operand is coerced to a string; the right must be an object.
                const key = switch (left) {
                    .string => |s| s,
                    .integer => |i| blk: {
                        var buf: [32]u8 = undefined;
                        const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                        const owned = try env.allocator.dupe(u8, s);
                        env.owned_strings.append(env.allocator, owned) catch {};
                        break :blk owned;
                    },
                    .float => |f| blk: {
                        var buf: [64]u8 = undefined;
                        const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.OutOfMemory;
                        const owned = try env.allocator.dupe(u8, s);
                        env.owned_strings.append(env.allocator, owned) catch {};
                        break :blk owned;
                    },
                    .boolean => |bv| if (bv) "true" else "false",
                    .symbol => |sym| blk: {
                        const prop_name = try ast.symbolPropertyName(env.allocator, sym.description);
                        env.owned_strings.append(env.allocator, prop_name) catch {};
                        break :blk prop_name;
                    },
                    else => return .{ .boolean = false },
                };
                return switch (right) {
                    .js_object => |obj| blk: {
                        var cur: ?*ast.ObjectValue = obj;
                        while (cur) |o| {
                            if (o.properties.contains(key)) break :blk .{ .boolean = true };
                            cur = o.prototype;
                        }
                        break :blk .{ .boolean = false };
                    },
                    .array => |arr| blk: {
                        if (std.mem.eql(u8, key, "length")) break :blk .{ .boolean = true };
                        const index = arrayKeyIndex(key) orelse break :blk ast.Value{ .boolean = false };
                        if (index >= arr.elements.items.len) break :blk .{ .boolean = false };
                        break :blk .{ .boolean = arr.elements.items[index] != .hole };
                    },
                    .string => |s| blk: {
                        const index = std.fmt.parseInt(usize, key, 10) catch break :blk ast.Value{ .boolean = false };
                        break :blk .{ .boolean = index < s.len };
                    },
                    else => .{ .boolean = false },
                };
            }

            if (b.operator == .InstanceOf) {
                // ECMAScript 12.9.4: left instanceof right.
                // If left is a primitive value, return false immediately.
                switch (left) {
                    .array, .js_object, .function, .closure, .generator, .iterator => {},
                    else => return .{ .boolean = false },
                }
                // Class constructors: walk the instance prototype chain.
                if (right == .js_object and right.js_object.properties.get("prototype") != null) {
                    const target = classPrototypeOf(right) orelse return .{ .boolean = false };
                    if (left == .js_object) {
                        var cur = left.js_object.prototype;
                        while (cur) |o| {
                            if (o == target) return .{ .boolean = true };
                            cur = o.prototype;
                        }
                    }
                    return .{ .boolean = false };
                }
                // Get the constructor name from the right operand.
                const constructor_name: ?[]const u8 = switch (right) {
                    .object => |obj_ptr| blk: {
                        const impl: *const builtinsTypes.BuiltinObjectImpl = @ptrCast(@alignCast(obj_ptr));
                        break :blk impl.name;
                    },
                    else => null,
                };
                const name = constructor_name orelse return .{ .boolean = false };
                // Check the left operand's type identity.
                return .{ .boolean = switch (left) {
                    .array => std.mem.eql(u8, name, "Array") or std.mem.eql(u8, name, "Object"),
                    .js_object => |obj| blk: {
                        const tag = obj.properties.get("@@type");
                        if (tag) |t| {
                            if (t == .string and std.mem.eql(u8, t.string, name)) break :blk true;
                            // Error subtypes: check @@subtype (e.g. "SyntaxError")
                            const subtype = obj.properties.get("@@subtype");
                            if (subtype) |st| {
                                if (st == .string and std.mem.eql(u8, st.string, name)) break :blk true;
                            }
                        }
                        // Plain objects match "Object" constructor.
                        break :blk std.mem.eql(u8, name, "Object");
                    },
                    else => false,
                } };
            }

            if (left == .big_int and right == .big_int) {
                const lb = left.big_int;
                const rb = right.big_int;
                // Allocate a result BigInt and dispatch by operator.
                const result = ast.BigIntValue.init(env.allocator) catch return error.OutOfMemory;
                env.bigints.append(env.allocator, result) catch {};
                switch (b.operator) {
                    .Plus => {
                        result.value.copy(lb.value.toConst()) catch return error.OutOfMemory;
                        result.value.add(&lb.value, &rb.value) catch return error.OutOfMemory;
                    },
                    .Minus => {
                        result.value.copy(lb.value.toConst()) catch return error.OutOfMemory;
                        result.value.sub(&lb.value, &rb.value) catch return error.OutOfMemory;
                    },
                    .Multiply => {
                        result.value.copy(lb.value.toConst()) catch return error.OutOfMemory;
                        result.value.mul(&lb.value, &rb.value) catch return error.OutOfMemory;
                    },
                    .Divide => {
                        var quot = ast.BigIntValue.init(env.allocator) catch return error.OutOfMemory;
                        env.bigints.append(env.allocator, quot) catch {};
                        quot.value.divFloor(&result.value, &lb.value, &rb.value) catch return error.OutOfMemory;
                        return .{ .big_int = result };
                    },
                    .Modulo => {
                        var quot = ast.BigIntValue.init(env.allocator) catch return error.OutOfMemory;
                        env.bigints.append(env.allocator, quot) catch {};
                        quot.value.divFloor(&result.value, &lb.value, &rb.value) catch return error.OutOfMemory;
                        return .{ .big_int = result };
                    },
                    .LessThan => return .{ .boolean = lb.compare(rb) == .lt },
                    .LessThanOrEqual => {
                        const ord = lb.compare(rb);
                        return .{ .boolean = ord == .lt or ord == .eq };
                    },
                    .GreaterThan => return .{ .boolean = lb.compare(rb) == .gt },
                    .GreaterThanOrEqual => {
                        const ord = lb.compare(rb);
                        return .{ .boolean = ord == .gt or ord == .eq };
                    },
                    .Equal, .StrictEqual => return .{ .boolean = lb.compare(rb) == .eq },
                    .NotEqual, .StrictNotEqual => return .{ .boolean = lb.compare(rb) != .eq },
                    .BitAnd, .BitOr, .BitXor, .LeftShift, .RightShift, .UnsignedRightShift => return error.UnsupportedOperator,
                    else => return error.UnsupportedOperator,
                }
                return .{ .big_int = result };
            }

            if (b.operator == .Exponent) {
                // ** is only supported for BigInt ** non-negative integer (matches ES2020).
                const exp_int: i64 = switch (right) {
                    .integer => |i| if (i < 0) return error.OutOfMemory else i,
                    .big_int => |bi| bi.toI64() orelse return error.OutOfMemory,
                    else => return error.UnsupportedOperator,
                };
                const base = switch (left) {
                    .big_int => |bi| bi.value,
                    .integer => |i| blk: {
                        const tmp = ast.BigIntValue.fromString(env.allocator, "0") catch return error.OutOfMemory;
                        env.bigints.append(env.allocator, tmp) catch {};
                        tmp.value.set(i) catch return error.OutOfMemory;
                        break :blk tmp.value;
                    },
                    .float => |f| {
                        // Number ** Number — promote to f64.
                        const e: f64 = switch (right) {
                            .integer => |i| @floatFromInt(i),
                            .float => |ff| ff,
                            else => unreachable,
                        };
                        return .{ .float = std.math.pow(f64, f, e) };
                    },
                    else => return error.UnsupportedOperator,
                };
                const result = ast.BigIntValue.init(env.allocator) catch return error.OutOfMemory;
                env.bigints.append(env.allocator, result) catch {};
                result.value.set(1) catch return error.OutOfMemory;
                var i: i64 = 0;
                while (i < exp_int) : (i += 1) {
                    result.value.mul(&result.value, &base) catch return error.OutOfMemory;
                }
                return .{ .big_int = result };
            }

            if (left == .integer and right == .integer) {
                const left_int = left.integer;
                const right_int = right.integer;

                // Handle overflow for arithmetic ops — fall back to float
                if (b.operator == .Plus) {
                    const ov = @addWithOverflow(left_int, right_int);
                    if (ov[1] != 0) {
                        return .{ .float = @as(f64, @floatFromInt(left_int)) + @as(f64, @floatFromInt(right_int)) };
                    }
                    return .{ .integer = ov[0] };
                }
                if (b.operator == .Minus) {
                    const ov = @subWithOverflow(left_int, right_int);
                    if (ov[1] != 0) {
                        return .{ .float = @as(f64, @floatFromInt(left_int)) - @as(f64, @floatFromInt(right_int)) };
                    }
                    return .{ .integer = ov[0] };
                }
                if (b.operator == .Multiply) {
                    const ov = @mulWithOverflow(left_int, right_int);
                    if (ov[1] != 0) {
                        return .{ .float = @as(f64, @floatFromInt(left_int)) * @as(f64, @floatFromInt(right_int)) };
                    }
                    return .{ .integer = ov[0] };
                }

                return switch (b.operator) {
                    .Divide => .{ .float = @as(f64, @floatFromInt(left_int)) / @as(f64, @floatFromInt(right_int)) },
                    .Modulo => .{ .integer = @mod(left_int, right_int) },
                    .LessThan => .{ .boolean = left_int < right_int },
                    .LessThanOrEqual => .{ .boolean = left_int <= right_int },
                    .GreaterThan => .{ .boolean = left_int > right_int },
                    .GreaterThanOrEqual => .{ .boolean = left_int >= right_int },
                    .Equal => .{ .boolean = left_int == right_int },
                    .NotEqual => .{ .boolean = left_int != right_int },
                    .StrictEqual => .{ .boolean = left_int == right_int },
                    .StrictNotEqual => .{ .boolean = left_int != right_int },
                    .BitAnd => .{ .integer = left_int & right_int },
                    .BitOr => .{ .integer = left_int | right_int },
                    .BitXor => .{ .integer = left_int ^ right_int },
                    .LeftShift => .{ .integer = left_int << @intCast(right_int) },
                    .RightShift => .{ .integer = left_int >> @intCast(right_int) },
                    .UnsignedRightShift => .{
                        .integer = @as(i64, @as(u32, @bitCast(@as(i32, @truncate(left_int)))) >> @as(u5, @intCast(right_int & 0x1f))),
                    },
                    else => return error.UnsupportedOperator,
                };
            }

            const toNum = struct {
                fn convert(val: ast.Value) f64 {
                    return switch (val) {
                        .integer => |i| @floatFromInt(i),
                        .float => |f| f,
                        .void => std.math.nan(f64),
                        .boolean => |bv| if (bv) 1.0 else 0.0,
                        .string => |s| std.fmt.parseFloat(f64, s) catch std.math.nan(f64),
                        .js_object => coercion.dateTimestamp(val) orelse std.math.nan(f64),
                        else => std.math.nan(f64),
                    };
                }
            }.convert;
            const left_num = toNum(left);
            const right_num = toNum(right);

            // ES spec: any relational comparison with NaN returns false
            if (std.math.isNan(left_num) or std.math.isNan(right_num)) {
                switch (b.operator) {
                    .LessThan, .LessThanOrEqual, .GreaterThan, .GreaterThanOrEqual => {
                        return .{ .boolean = false };
                    },
                    else => {},
                }
            }

            return switch (b.operator) {
                .Plus => .{ .float = left_num + right_num },
                .Minus => .{ .float = left_num - right_num },
                .Multiply => .{ .float = left_num * right_num },
                .Divide => .{ .float = left_num / right_num },
                .Modulo => .{ .float = @mod(left_num, right_num) },
                .LessThan => .{ .boolean = left_num < right_num },
                .LessThanOrEqual => .{ .boolean = left_num <= right_num },
                .GreaterThan => .{ .boolean = left_num > right_num },
                .GreaterThanOrEqual => .{ .boolean = left_num >= right_num },
                .Equal => .{ .boolean = left_num == right_num },
                .NotEqual => .{ .boolean = left_num != right_num },
                .StrictEqual => .{ .boolean = left_num == right_num },
                .StrictNotEqual => .{ .boolean = left_num != right_num },
                .BitAnd => .{ .integer = @as(i64, @intFromFloat(left_num)) & @as(i64, @intFromFloat(right_num)) },
                .BitOr => .{ .integer = @as(i64, @intFromFloat(left_num)) | @as(i64, @intFromFloat(right_num)) },
                .BitXor => .{ .integer = @as(i64, @intFromFloat(left_num)) ^ @as(i64, @intFromFloat(right_num)) },
                .LeftShift => .{ .integer = @as(i64, @intFromFloat(left_num)) << @intCast(@as(i64, @intFromFloat(right_num))) },
                .RightShift => .{ .integer = @as(i64, @intFromFloat(left_num)) >> @intCast(@as(i64, @intFromFloat(right_num))) },
                .UnsignedRightShift => .{
                    .integer = @as(i64, @as(u32, @bitCast(@as(i32, @truncate(@as(i64, @intFromFloat(left_num)))))) >> @as(u5, @intCast(@as(u64, @bitCast(@as(i64, @intFromFloat(right_num)))) & 0x1f))),
                },
                else => return error.UnsupportedOperator,
            };
        },
        .Assignment => |a| {
            const value = try evaluate(a.value, env);
            try env.setInScope(a.name, value);
            return value;
        },
        .UpdateExpression => |u| {
            // Resolve the current value from the operand
            const current = blk: {
                switch (u.operand.*) {
                    .Identifier => |ident| {
                        const val = env.get(ident.name) orelse break :blk null;
                        break :blk val;
                    },
                    .MemberAccess => |m| {
                        const obj_val = try evaluate(m.object, env);
                        if (obj_val == .js_object) {
                            if (obj_val.js_object.properties.get(m.property)) |val| {
                                break :blk val;
                            }
                        }
                        break :blk null;
                    },
                    .ArrayIndex => |ai| {
                        const obj_val = try evaluate(ai.array, env);
                        const idx_val = try evaluate(ai.index, env);
                        if (obj_val == .array) {
                            const index = switch (idx_val) {
                                .integer => |i| if (i >= 0) @as(usize, @intCast(i)) else break :blk null,
                                else => break :blk null,
                            };
                            if (index < obj_val.array.elements.items.len) {
                                const val = obj_val.array.elements.items[index];
                                break :blk if (val == .hole) null else val;
                            }
                        }
                        break :blk null;
                    },
                    else => return error.InvalidAssignmentTarget,
                }
            } orelse return error.UndefinedVariable;

            const new_val = blk: {
                switch (current) {
                    .big_int => |bi| {
                        const result = ast.BigIntValue.init(env.allocator) catch return error.OutOfMemory;
                        env.bigints.append(env.allocator, result) catch {};
                        const one_str = if (u.operator == .Increment) "1" else "-1";
                        const delta = ast.BigIntValue.fromString(env.allocator, one_str) catch return error.OutOfMemory;
                        defer env.allocator.free(delta.value.toString(env.allocator, 10, .lower) catch "");
                        env.bigints.append(env.allocator, delta) catch {};
                        if (u.operator == .Increment) {
                            result.value.add(&bi.value, &delta.value) catch return error.OutOfMemory;
                        } else {
                            result.value.sub(&bi.value, &delta.value) catch return error.OutOfMemory;
                        }
                        break :blk ast.Value{ .big_int = result };
                    },
                    .integer => |i| {
                        if (u.operator == .Increment) {
                            const ov = @addWithOverflow(i, 1);
                            if (ov[1] != 0) {
                                break :blk ast.Value{ .float = @as(f64, @floatFromInt(i)) + 1.0 };
                            }
                            break :blk ast.Value{ .integer = ov[0] };
                        } else {
                            const ov = @subWithOverflow(i, 1);
                            if (ov[1] != 0) {
                                break :blk ast.Value{ .float = @as(f64, @floatFromInt(i)) - 1.0 };
                            }
                            break :blk ast.Value{ .integer = ov[0] };
                        }
                    },
                    .float => |f| {
                        if (u.operator == .Increment) {
                            break :blk ast.Value{ .float = f + 1.0 };
                        } else {
                            break :blk ast.Value{ .float = f - 1.0 };
                        }
                    },
                    else => return error.InvalidAssignmentTarget,
                }
            };
            // Store the new value back
            switch (u.operand.*) {
                .Identifier => |ident| try env.setInScope(ident.name, new_val),
                .MemberAccess => |m| {
                    const obj_val = try evaluate(m.object, env);
                    if (obj_val == .js_object) {
                        try obj_val.js_object.properties.put(m.property, new_val);
                    }
                },
                .ArrayIndex => |ai| {
                    const obj_val = try evaluate(ai.array, env);
                    const idx_val = try evaluate(ai.index, env);
                    if (obj_val == .array) {
                        const index = switch (idx_val) {
                            .integer => |i| if (i >= 0) @as(usize, @intCast(i)) else return error.InvalidAssignmentTarget,
                            else => return error.InvalidAssignmentTarget,
                        };
                        try obj_val.array.set(index, new_val);
                    }
                },
                else => return error.InvalidAssignmentTarget,
            }
            return if (u.prefix) new_val else current;
        },
        .AwaitExpression => |a| {
            const awaited = try evaluate(a.value, env);
            return try awaitValue(env, awaited);
        },
        .YieldExpression => |y| {
            if (y.is_star) {
                // yield* — delegate to another generator or iterable
                // On re-entry after a yield, cached delegate state may persist
                
                // First entry: evaluate the expression and set up delegation
                const yield_star_active = env.yield_star_gen != null or env.yield_star_array != null or env.yield_star_iterator != null or env.yield_star_string != null or env.yield_star_js_iterator != null;
                if (!yield_star_active) {
                    const iterable = if (y.value) |v| try evaluate(v, env) else @as(ast.Value, .{ .void = {} });
                    switch (iterable) {
                        .generator => |gen| {
                            env.yield_star_gen = gen;
                        },
                        .array => |arr| {
                            env.yield_star_array = arr;
                            env.yield_star_index = 0;
                        },
                        .string => |s| {
                            env.yield_star_string = s;
                            env.yield_star_index = 0;
                        },
                        .iterator => |it| {
                            env.yield_star_iterator = it;
                        },
                        .js_object => |obj| {
                            if (obj.properties.get("@@asyncIterator")) |iterator_fn| {
                                const iterator_val = try callFunctionValue(iterator_fn, &.{}, env, .{ .js_object = obj });
                                if (iterator_val == .js_object) {
                                    env.yield_star_js_iterator = iterator_val.js_object;
                                }
                            } else if (obj.properties.get("@@iterator")) |iterator_fn| {
                                const iterator_val = try callFunctionValue(iterator_fn, &.{}, env, .{ .js_object = obj });
                                if (iterator_val == .js_object) {
                                    env.yield_star_js_iterator = iterator_val.js_object;
                                }
                            }
                        },
                        else => {},
                    }
                }
                
                // Handle generator delegation (cached or fresh)
                if (env.yield_star_gen) |delegate| {
                    while (true) {
                        const next_raw = try evaluateGeneratorNext(delegate, env);
                        const next_val = if (env.is_async_generator) try awaitValue(env, next_raw) else next_raw;
                        if (next_val != .js_object) break;
                        const done_val = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                        const is_done = switch (done_val) {
                            .boolean => |b| b,
                            else => true,
                        };
                        const raw_val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                        const val = if (env.is_async_generator) try awaitValue(env, raw_val) else raw_val;
                        if (is_done) {
                            env.yield_star_gen = null;
                            return val;
                        }
                        env.yield_caught_by_loop = true;
                        env.yield_hit = true;
                        env.yield_value = val;
                        return val;
                    }
                    env.yield_star_gen = null;
                    return .{ .void = {} };
                }
                
                // Handle array delegation (cached across re-entries)
                if (env.yield_star_array) |delegate| {
                    const i = env.yield_star_index;
                    while (i < delegate.elements.items.len) {
                        const elem = delegate.elements.items[i];
                        env.yield_star_index = i + 1;
                        env.yield_caught_by_loop = true;
                        env.yield_hit = true;
                        env.yield_value = elem;
                        return elem;
                    }
                    env.yield_star_array = null;
                    env.yield_star_index = 0;
                    return .{ .void = {} };
                }
                
                // Handle string delegation
                if (env.yield_star_string) |delegate| {
                    const i = env.yield_star_index;
                    while (i < delegate.len) {
                        const cp_len = std.unicode.utf8ByteSequenceLength(delegate[i]) catch 1;
                        const char = delegate[i .. i + cp_len];
                        env.yield_star_index = i + cp_len;
                        env.yield_caught_by_loop = true;
                        env.yield_hit = true;
                        env.yield_value = .{ .string = char };
                        return .{ .string = char };
                    }
                    env.yield_star_string = null;
                    env.yield_star_index = 0;
                    return .{ .void = {} };
                }
                
                // Handle iterator delegation
                if (env.yield_star_iterator) |delegate| {
                    const next_val = delegate.next(env.allocator, &env.arrays, &env.objects);
                    if (next_val == .js_object) {
                        const done = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                        if (done != .boolean or !done.boolean) {
                            const val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                            env.yield_caught_by_loop = true;
                            env.yield_hit = true;
                            env.yield_value = val;
                            return val;
                        }
                    }
                    env.yield_star_iterator = null;
                    return .{ .void = {} };
                }
                
                // Handle js_object iterator delegation (from @@iterator protocol)
                if (env.yield_star_js_iterator) |delegate| {
                    while (true) {
                        const next_fn = delegate.properties.get("next") orelse {
                            env.yield_star_js_iterator = null;
                            return .{ .void = {} };
                        };
                        const next_raw = try callFunctionValue(next_fn, &.{}, env, .{ .js_object = delegate });
                        const next_val = if (env.is_async_generator) try awaitValue(env, next_raw) else next_raw;
                        if (next_val != .js_object) {
                            env.yield_star_js_iterator = null;
                            return .{ .void = {} };
                        }
                        const done_val = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                        const is_done = switch (done_val) {
                            .boolean => |b| b,
                            else => true,
                        };
                        const raw_val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                        const val = if (env.is_async_generator) try awaitValue(env, raw_val) else raw_val;
                        if (is_done) {
                            env.yield_star_js_iterator = null;
                            return val;
                        }
                        env.yield_caught_by_loop = true;
                        env.yield_hit = true;
                        env.yield_value = val;
                        return val;
                    }
                    env.yield_star_js_iterator = null;
                    return .{ .void = {} };
                }
                
                return .{ .void = {} };
            } else {
                const raw_val: ast.Value = if (y.value) |v| try evaluate(v, env) else .{ .void = {} };
                const val = if (env.is_async_generator) try awaitValue(env, raw_val) else raw_val;
                env.yield_hit = true;
                env.yield_value = val;
                return val;
            }
        },
        .ConstantDeclaration => |c| {
            // const always has a value at the AST level — the parser
            // rejects `for (const x;;)` so c.value.? is safe here.
            const val_expr = c.value.?;
            if (val_expr.* == .FunctionDeclaration or val_expr.* == .ArrowFunction or val_expr.* == .GeneratorDeclaration) {
                try env.setFunction(c.name, val_expr);
                try env.setConstant(c.name, .{ .float = 0.0 });
                return .{ .float = 0.0 };
            } else {
                const value = try evaluate(val_expr, env);
                try env.setConstant(c.name, value);
                return value;
            }
        },
        .VariableDeclaration => |v| {
            if (v.value) |val_expr| {
                if (val_expr.* == .FunctionDeclaration or val_expr.* == .ArrowFunction or val_expr.* == .GeneratorDeclaration) {
                    try env.setFunction(v.name, val_expr);
                    try env.setVar(v.name, .{ .float = 0.0 });
                    return .{ .float = 0.0 };
                }
                const value = try evaluate(val_expr, env);
                try env.setVar(v.name, value);
                return value;
            }
            // No initializer — declared but undefined (`for (var i; ...)`)
            try env.setVar(v.name, .{ .void = {} });
            return .{ .void = {} };
        },
        .LetDeclaration => |v| {
            if (v.value) |val_expr| {
                if (val_expr.* == .FunctionDeclaration or val_expr.* == .ArrowFunction or val_expr.* == .GeneratorDeclaration) {
                    try env.setFunction(v.name, val_expr);
                    try env.setLet(v.name, .{ .float = 0.0 });
                    return .{ .float = 0.0 };
                }
                const value = try evaluate(val_expr, env);
                try env.setLet(v.name, value);
                return value;
            }
            // No initializer — declared but undefined (`for (let x;;)`)
            try env.setLet(v.name, .{ .void = {} });
            return .{ .void = {} };
        },
        .BlockStatement => |b| {
            var has_block_scope = false;
            if (b.is_scope) {
                for (b.statements) |stmt| {
                    if (stmt.* == .LetDeclaration or stmt.* == .ConstantDeclaration) {
                        has_block_scope = true;
                        break;
                    }
                }
            }

            if (!has_block_scope) {
                var result: ast.Value = .{ .float = 0.0 };
                for (b.statements) |stmt| {
                    if (stmt.* == .ReturnStatement) {
                        const ret_stmt = stmt.ReturnStatement;
                        // A return nested in a block must abort the enclosing
                        // function, not just this block.
                        env.return_hit = true;
                        if (ret_stmt.value) |val| {
                            return try evaluate(val, env);
                        } else {
                            return .{ .void = {} };
                        }
                    }
                    result = try evaluate(stmt, env);
                    if (env.return_hit or env.break_hit or env.continue_hit) break;
                }
                return result;
            }

            var block_env = try Environment.initBlock(env.allocator, env);
            defer block_env.deinit();
            predeclareLexicals(&block_env, b.statements);

            var result: ast.Value = .{ .float = 0.0 };
            for (b.statements) |stmt| {
                if (stmt.* == .ReturnStatement) {
                    const ret_stmt = stmt.ReturnStatement;
                    block_env.return_hit = true;
                    env.return_hit = true;
                    if (ret_stmt.value) |val| {
                        return try evaluate(val, &block_env);
                    } else {
                        return .{ .void = {} };
                    }
                }

                result = evaluate(stmt, &block_env) catch |err| {
                    if (block_env.throw_hit) {
                        env.throw_hit = true;
                        env.throw_value = block_env.throw_value;
                    }
                    return err;
                };
                if (block_env.return_hit or block_env.break_hit or block_env.continue_hit) break;
            }
            return result;
        },
        .ForLoop => |f| {
            var pre_limit: ?f64 = null;
            if (f.condition) |cond| {
                if (cond.* == .BinaryExpression) {
                    const be = cond.BinaryExpression;
                    if (be.operator == .LessThan and be.left.* == .Identifier) {
                        pre_limit = switch (be.right.*) {
                            .FloatLiteral => |v| v.value,
                            .IntegerLiteral => |v| @floatFromInt(v.value),
                            else => null,
                        };
                        if (pre_limit == null) {
                            const val = evaluate(be.right, env) catch null;
                            if (val) |v| {
                                pre_limit = switch (v) {
                                    .float => |fval| fval,
                                    .integer => |ival| @floatFromInt(ival),
                                    else => null,
                                };
                            }
                        }
                    }
                }
            }
            const is_let_init = if (f.init) |init| blk: {
                if (init.* == .LetDeclaration) break :blk true;
                if (init.* == .BlockStatement) {
                    for (init.BlockStatement.statements) |s| {
                        if (s.* == .LetDeclaration or s.* == .ConstantDeclaration) break :blk true;
                    }
                }
                break :blk false;
            } else false;
            // A for-let loop whose body creates a closure needs a fresh
            // binding per iteration so each closure sees its own copy.
            const per_iter = is_let_init and (ast.containsClosure(f.body) or env.is_generator);
            if (!per_iter) {
                debugPrint("[OPTIMIZATION] Trying optimizeSimpleForLoop, pre_limit={?}\n", .{pre_limit});
                if (try optimizations.optimizeSimpleForLoop(f, env, pre_limit)) |result| {
                    debugPrint("[OPTIMIZATION] SUCCESS!\n", .{});
                    return result;
                }
                debugPrint("[OPTIMIZATION] FAILED - falling through\n", .{});
            }

            var scope_names = std.ArrayList([]const u8).initCapacity(env.allocator, 0) catch {
                return error.OutOfMemory;
            };
            defer scope_names.deinit(env.allocator);
            if (per_iter) {
                if (f.init) |init| {
                    switch (init.*) {
                        .LetDeclaration => |v| try scope_names.append(env.allocator, v.name),
                        .ConstantDeclaration => |v| try scope_names.append(env.allocator, v.name),
                        .BlockStatement => |b| {
                            for (b.statements) |st| {
                                switch (st.*) {
                                    .LetDeclaration => |v| try scope_names.append(env.allocator, v.name),
                                    .ConstantDeclaration => |v| try scope_names.append(env.allocator, v.name),
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                }
            }

            var loop_env_buf: Environment = undefined;
            var eval_env: *Environment = undefined;
            if (per_iter) {
                if (env.for_yield_iter_env) |saved| {
                    eval_env = @alignCast(@ptrCast(saved));
                } else {
                    eval_env = try Environment.initIterHeap(env.allocator, env);
                }
            } else if (is_let_init) {
                loop_env_buf = try Environment.initBlock(env.allocator, env);
                eval_env = &loop_env_buf;
            } else {
                eval_env = env;
            }
            defer if (is_let_init and !per_iter) loop_env_buf.deinit();

            var result: ast.Value = .{ .float = 0.0 };
            var loop_yielded = false;

            // Run init on first entry; skip on generator yield re-entry
            if (f.init) |init| {
                if (env.for_yield_node != @as(?*const anyopaque, @ptrCast(node))) {
                    // Unroll BlockStatement inits directly into eval_env so let/const
                    // declarations are visible to the condition/body/increment.
                    if (init.* == .BlockStatement) {
                        for (init.BlockStatement.statements) |s| {
                            _ = try evaluate(s, eval_env);
                        }
                    } else {
                        _ = try evaluate(init, eval_env);
                    }
                }
            }

            const loop_var_name: ?[]const u8 = if (f.condition) |cond|
                if (cond.* == .BinaryExpression)
                    if (cond.BinaryExpression.left.* == .Identifier)
                        cond.BinaryExpression.left.Identifier.name
                    else
                        null
                else
                    null
    else
        null;

    const my_label = env.pending_loop_label;
    env.pending_loop_label = null;
    while (true) {
        if (pre_limit != null and loop_var_name != null) {
                    const current_val = eval_env.get(loop_var_name.?) orelse break;
                    const current_f: f64 = switch (current_val) {
                        .float => |v| v,
                        .integer => |v| @floatFromInt(v),
                        else => break,
                    };
                    if (current_f >= pre_limit.?) break;
                } else if (f.condition) |cond| {
                    const cond_val = try evaluate(cond, eval_env);
                    const is_false = switch (cond_val) {
                        .boolean => |bv| !bv,
                        .float => |fv| fv == 0.0,
                        .integer => |iv| iv == 0,
                        else => false,
                    };
                    if (is_false) break;
                }

                result = try evaluate(f.body, eval_env);
                if (eval_env.yield_hit) {
                    const yielded_value = eval_env.yield_value;
                    // Track which for-loop node yielded so init is skipped on re-entry
                    env.for_yield_node = @ptrCast(node);
                    loop_yielded = true;
                    // If yield came from an active yield*, don't advance the loop variable.
                    // yield* spans multiple generator.next() calls — the loop should not
                    // advance until yield* completes and the body finishes normally.
                    if (eval_env.yield_star_gen == null and eval_env.yield_star_array == null) {
                        if (per_iter) {
                            const next_scope = try Environment.initIterHeap(env.allocator, env);
                            for (scope_names.items) |n| {
                                if (eval_env.get(n)) |v| next_scope.setVar(n, v) catch {};
                            }
                            eval_env = next_scope;
                        }
                        if (f.increment) |inc| {
                            _ = try evaluate(inc, eval_env);
                        }
                    }
                    // Persist the scope AFTER advancing the loop variable so the
                    // next next() re-enters with the incremented value.
                    env.for_yield_iter_env = @ptrCast(eval_env);
                    eval_env.yield_caught_by_loop = true;
                    result = yielded_value;
                    if (eval_env != env) {
                        env.yield_hit = true;
                        env.yield_value = yielded_value;
                        env.yield_caught_by_loop = true;
                    }
                    eval_env.yield_hit = false; // Consume so outer loops don't also catch it
                    break;
                }
                if (eval_env.return_hit) break;
                if (eval_env.break_hit) {
                    const matches = (eval_env.break_label == null) or
                        (my_label != null and std.mem.eql(u8, eval_env.break_label.?, my_label.?));
                    if (matches) {
                        eval_env.break_hit = false;
                        eval_env.break_label = null;
                    }
                    break;
                }
                if (eval_env.continue_hit) {
                    const matches = (eval_env.continue_label == null) or
                        (my_label != null and std.mem.eql(u8, eval_env.continue_label.?, my_label.?));
                    if (matches) {
                        eval_env.continue_hit = false;
                        eval_env.continue_label = null;
                        if (per_iter) {
                            const next_scope = try Environment.initIterHeap(env.allocator, env);
                            for (scope_names.items) |n| {
                                if (eval_env.get(n)) |v| next_scope.setVar(n, v) catch {};
                            }
                            eval_env = next_scope;
                        }
                        if (f.increment) |inc| {
                            _ = try evaluate(inc, eval_env);
                        }
                        continue;
                    }
                    break;
                }
                if (per_iter) {
                    const next_scope = try Environment.initIterHeap(env.allocator, env);
                    for (scope_names.items) |n| {
                        if (eval_env.get(n)) |v| next_scope.setVar(n, v) catch {};
                    }
                    eval_env = next_scope;
                }
                if (f.increment) |inc| {
                    _ = try evaluate(inc, eval_env);
                }
            }

            // For-loop completed without yielding — clear for_yield_node
            if (!loop_yielded and env.for_yield_node == @as(?*const anyopaque, @ptrCast(node))) {
                env.for_yield_node = null;
                env.for_yield_iter_env = null;
            }
            return result;
        },
        .ForOfLoop => |f| {
            var result: ast.Value = .{ .float = 0.0 };
            const fo_my_label = env.pending_loop_label;
            env.pending_loop_label = null;

            // `for await` eagerly awaits the iterable into an array, then reuses
            // the cache-friendly array loop below. This keeps yield/break/continue
            // re-entry working inside async generators.
            if (f.is_await and env.for_of_array == null and env.for_of_gen == null) {
                const awaited_iterable = try evaluate(f.iterable, env);
                env.for_of_array = try collectForAwaitValues(env, awaited_iterable);
                env.for_of_array_index = 0;
            }

            // On re-entry after yield, check for cached iteration state first
            // (these fields persist in the generator's environment)
            if (env.for_of_gen) |cached_gen| {
                var block_env_buf: Environment = undefined;
                const loop_env: *Environment = if (f.kind == .Let or f.kind == .Const) blk: {
                    block_env_buf = try Environment.initBlock(env.allocator, env);
                    break :blk &block_env_buf;
                } else env;
                defer if (f.kind == .Let or f.kind == .Const) block_env_buf.deinit();

                // If yield_star is active from a previous body evaluation,
                // DON'T advance the cached generator — let yield* continue delegating.
                if (env.yield_star_gen == null and env.yield_star_array == null and env.yield_star_iterator == null and env.yield_star_string == null) {
                    const next_val = try evaluateGeneratorNext(cached_gen, env);
                    if (next_val != .js_object) {
                        env.for_of_gen = null;
                        return result;
                    }
                    const done_val = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                    const is_done = switch (done_val) {
                        .boolean => |b| b,
                        else => true,
                    };
                    if (is_done) {
                        env.for_of_gen = null;
                        return result;
                    }
                    const val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                    try setLoopVar(loop_env, f.kind, f.variable, val);
                }
                result = try evaluate(f.body, loop_env);
                if (loop_env.yield_hit) {
                    // Propagate yield_star state from loop_env to outer env
                    if (loop_env.yield_star_gen != null) env.yield_star_gen = loop_env.yield_star_gen;
                    if (loop_env.yield_star_array != null) {
                        env.yield_star_array = loop_env.yield_star_array;
                        env.yield_star_index = loop_env.yield_star_index;
                    }
                    env.yield_hit = true;
                    env.yield_value = loop_env.yield_value;
                    env.yield_caught_by_loop = true;
                    result = loop_env.yield_value;
                    loop_env.yield_hit = false;
                }
                if (loop_env.break_hit) {
                    consumeBreak(loop_env, fo_my_label);
                    env.for_of_gen = null;
                    return result;
                }
                if (loop_env.continue_hit) {
                    if (consumeContinue(loop_env, fo_my_label)) {
                        return result;
                    }
                    // Labeled continue for outer loop — propagate
                    return result;
                }
                return result;
            }

            if (env.for_of_array) |cached_arr| {
                var block_env_buf: Environment = undefined;
                const loop_env: *Environment = if (f.kind == .Let or f.kind == .Const) blk: {
                    block_env_buf = try Environment.initBlock(env.allocator, env);
                    break :blk &block_env_buf;
                } else env;
                defer if (f.kind == .Let or f.kind == .Const) block_env_buf.deinit();

                var i = env.for_of_array_index;
                while (i < cached_arr.elements.items.len) {
                    // If yield_star is still active from a previous body evaluation,
                    // DON'T set the loop variable — keep the old value so yield*
                    // continues delegating from the SAME element.
                    const yield_star_active = env.yield_star_gen != null or env.yield_star_array != null;
                    if (!yield_star_active) {
                        const val = cached_arr.elements.items[i];
                        try setLoopVar(loop_env, f.kind, f.variable, val);
                    }
                    // Restore yield_star state to loop_env before body evaluation
                    // (loop_env is freshly created, so yield_star_* starts null)
                    if (env.yield_star_gen != null) loop_env.yield_star_gen = env.yield_star_gen;
                    if (env.yield_star_array != null) {
                        loop_env.yield_star_array = env.yield_star_array;
                        loop_env.yield_star_index = env.yield_star_index;
                    }
                    result = try evaluate(f.body, loop_env);
                    if (loop_env.yield_hit) {
                        // Propagate yield_star state from loop_env back to outer env
                        if (loop_env.yield_star_gen != null) env.yield_star_gen = loop_env.yield_star_gen;
                        if (loop_env.yield_star_array != null) {
                            env.yield_star_array = loop_env.yield_star_array;
                            env.yield_star_index = loop_env.yield_star_index;
                        } else if (env.yield_star_array != null) {
                            // yield* exhausted: clear stale state on env
                            env.yield_star_array = null;
                            env.yield_star_index = 0;
                        }
                        env.yield_hit = true;
                        env.yield_value = loop_env.yield_value;
                        env.yield_caught_by_loop = true;
                        result = loop_env.yield_value;
                        loop_env.yield_hit = false;
                        // Always persist current array position for re-entry
                        // If yield* is still active, keep position (don't advance).
                        // Otherwise advance to next element.
                        const still_active = env.yield_star_gen != null or env.yield_star_array != null;
                        if (still_active) {
                            env.for_of_array_index = i;
                        } else {
                            env.for_of_array_index = i + 1;
                        }
                        return result;
                    }
                    // Body completed without yield — clear yield_star state on env
                    // (yield* was exhausted or wasn't used)
                    env.yield_star_array = loop_env.yield_star_array;
                    env.yield_star_gen = loop_env.yield_star_gen;
                    if (loop_env.return_hit) break;
                    if (loop_env.break_hit) {
                        consumeBreak(loop_env, fo_my_label);
                        env.for_of_array = null;
                        return result;
                    }
                    if (loop_env.continue_hit) {
                        if (consumeContinue(loop_env, fo_my_label)) {
                            i += 1;
                            env.for_of_array_index = i;
                            continue;
                        }
                        break;
                    }
                    i += 1;
                    // Persist current position across re-entries
                    env.for_of_array_index = i;
                }
                // Array exhausted
                env.for_of_array = null;
                return result;
            }

            // First entry: evaluate iterable and start fresh
            const iterable = try evaluate(f.iterable, env);

            var block_env_buf: Environment = undefined;
            const loop_env: *Environment = if (f.kind == .Let or f.kind == .Const) blk: {
                block_env_buf = try Environment.initBlock(env.allocator, env);
                break :blk &block_env_buf;
            } else env;
            defer if (f.kind == .Let or f.kind == .Const) block_env_buf.deinit();

            switch (iterable) {
                .array => |arr| {
                    var i: usize = 0;
                    while (i < arr.elements.items.len) {
                        const val = arr.elements.items[i];
                        try setLoopVar(loop_env, f.kind, f.variable, val);
                        result = try evaluate(f.body, loop_env);
                        if (loop_env.yield_hit) {
                            // Propagate yield_star state from loop_env to outer env
                            if (loop_env.yield_star_gen != null) env.yield_star_gen = loop_env.yield_star_gen;
                            if (loop_env.yield_star_array != null) {
                                env.yield_star_array = loop_env.yield_star_array;
                                env.yield_star_index = loop_env.yield_star_index;
                            } else if (env.yield_star_array != null) {
                                // yield* exhausted: clear stale state on env
                                env.yield_star_array = null;
                                env.yield_star_index = 0;
                            }
                            env.yield_hit = true;
                            env.yield_value = loop_env.yield_value;
                            env.yield_caught_by_loop = true;
                            result = loop_env.yield_value;
                            loop_env.yield_hit = false;
                            env.for_of_array = arr;
                            // Always persist current array position for re-entry
                            const still_active = env.yield_star_gen != null or env.yield_star_array != null;
                            if (still_active) {
                                env.for_of_array_index = i;
                            } else {
                                env.for_of_array_index = i + 1;
                            }
                            break;
                        }
                        if (loop_env.return_hit) break;
                if (loop_env.break_hit) {
                    consumeBreak(loop_env, fo_my_label);
                    break;
                }
                        if (loop_env.continue_hit) {
                            if (consumeContinue(loop_env, fo_my_label)) {
                                i += 1;
                                continue;
                            }
                            break;
                        }
                        // Clear stale yield_star state after body completes without yield
                        env.yield_star_array = loop_env.yield_star_array;
                        env.yield_star_gen = loop_env.yield_star_gen;
                        i += 1;
                    }
                },
                .string => |s| {
                    var i: usize = 0;
                    while (i < s.len) {
                        const cp_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
                        const char = s[i .. i + cp_len];
                        try setLoopVar(loop_env, f.kind, f.variable, .{ .string = char });
                        result = try evaluate(f.body, loop_env);
                        if (loop_env.yield_hit) {
                            // Propagate yield_star state from loop_env to outer env
                            if (loop_env.yield_star_gen != null) env.yield_star_gen = loop_env.yield_star_gen;
                            if (loop_env.yield_star_array != null) {
                                env.yield_star_array = loop_env.yield_star_array;
                                env.yield_star_index = loop_env.yield_star_index;
                            } else if (env.yield_star_array != null) {
                                // yield* exhausted: clear stale state on env
                                env.yield_star_array = null;
                                env.yield_star_index = 0;
                            }
                            env.yield_hit = true;
                            env.yield_value = loop_env.yield_value;
                            env.yield_caught_by_loop = true;
                            result = loop_env.yield_value;
                            loop_env.yield_hit = false;
                            break;
                        }
                        if (loop_env.return_hit) break;
                if (loop_env.break_hit) {
                    consumeBreak(loop_env, fo_my_label);
                    break;
                }
                        if (loop_env.continue_hit) {
                            if (consumeContinue(loop_env, fo_my_label)) {
                                i += cp_len;
                                continue;
                            }
                            break;
                        }
                        i += cp_len;
                    }
                },
                .js_object => |obj| {
                    if (obj.properties.get("@@iterator")) |iter_fn| {
                        const it = try callFunctionValue(iter_fn, &[_]ast.Value{}, env, .{ .js_object = obj });
                        if (it == .js_object) {
                            const iterator_obj = it.js_object;
                            while (true) {
                                const next_fn = iterator_obj.properties.get("next") orelse break;
                                const next_res = try callFunctionValue(next_fn, &[_]ast.Value{}, env, .{ .js_object = iterator_obj });
                                if (next_res != .js_object) break;
                                const done_val = next_res.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                                const is_done = switch (done_val) {
                                    .boolean => |b| b,
                                    else => true,
                                };
                                if (is_done) break;
                                const val = next_res.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                                try setLoopVar(loop_env, f.kind, f.variable, val);
                                result = try evaluate(f.body, loop_env);
                                if (loop_env.yield_hit) {
                                    if (loop_env.yield_star_gen != null) env.yield_star_gen = loop_env.yield_star_gen;
                                    if (loop_env.yield_star_array != null) {
                                        env.yield_star_array = loop_env.yield_star_array;
                                        env.yield_star_index = loop_env.yield_star_index;
                                    }
                                    env.yield_hit = true;
                                    env.yield_value = loop_env.yield_value;
                                    env.yield_caught_by_loop = true;
                                    result = loop_env.yield_value;
                                    loop_env.yield_hit = false;
                                    break;
                                }
                                if (loop_env.return_hit) break;
                                if (loop_env.break_hit) {
                                    consumeBreak(loop_env, fo_my_label);
                                    break;
                                }
                                if (loop_env.continue_hit) {
                                    if (consumeContinue(loop_env, fo_my_label)) continue;
                                    break;
                                }
                            }
                        }
                        return result;
                    }
                    const type_tag = obj.properties.get("@@type");
                    var handled = false;
                    if (type_tag != null and type_tag.? == .string) {
                        if (std.mem.eql(u8, type_tag.?.string, "Set")) {
                            handled = true;
                            if (obj.properties.get("values")) |vals| {
                                if (vals == .array) {
                                    for (vals.array.elements.items) |val| {
                                        try setLoopVar(loop_env, f.kind, f.variable, val);
                                        result = try evaluate(f.body, loop_env);
                                        if (loop_env.yield_hit) {
                                            env.yield_hit = true;
                                            env.yield_value = loop_env.yield_value;
                                            env.yield_caught_by_loop = true;
                                            result = loop_env.yield_value;
                                            loop_env.yield_hit = false;
                                            break;
                                        }
                                        if (loop_env.return_hit) break;
                                        if (loop_env.break_hit) {
                                            consumeBreak(loop_env, fo_my_label);
                                            break;
                                        }
                                        if (loop_env.continue_hit) {
                                            if (consumeContinue(loop_env, fo_my_label)) {
                                                continue;
                                            }
                                            break;
                                        }
                                    }
                                }
                            }
                        } else if (std.mem.eql(u8, type_tag.?.string, "Map")) {
                            handled = true;
                            if (obj.properties.get("entries")) |ents| {
                                if (ents == .array) {
                                    for (ents.array.elements.items) |entry| {
                                        try setLoopVar(loop_env, f.kind, f.variable, entry);
                                        result = try evaluate(f.body, loop_env);
                                        if (loop_env.yield_hit) {
                                            env.yield_hit = true;
                                            env.yield_value = loop_env.yield_value;
                                            env.yield_caught_by_loop = true;
                                            result = loop_env.yield_value;
                                            loop_env.yield_hit = false;
                                            break;
                                        }
                                        if (loop_env.return_hit) break;
                                        if (loop_env.break_hit) {
                                            consumeBreak(loop_env, fo_my_label);
                                            break;
                                        }
                                        if (loop_env.continue_hit) {
                                            if (consumeContinue(loop_env, fo_my_label)) {
                                                continue;
                                            }
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if (!handled) return error.TypeError;
                },
                .generator => |gen| {
                    // Cache the generator for re-entry
                    env.for_of_gen = gen;
                    while (true) {
                        const next_val = try evaluateGeneratorNext(gen, env);
                        if (next_val != .js_object) {
                            env.for_of_gen = null;
                            break;
                        }
                        const done_val = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                        const is_done = switch (done_val) {
                            .boolean => |b| b,
                            else => true,
                        };
                        if (is_done) {
                            env.for_of_gen = null;
                            break;
                        }
                        const val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                        try setLoopVar(loop_env, f.kind, f.variable, val);
                        result = try evaluate(f.body, loop_env);
                        if (loop_env.yield_hit) {
                            // Propagate yield_star state from loop_env to outer env
                            if (loop_env.yield_star_gen != null) env.yield_star_gen = loop_env.yield_star_gen;
                            if (loop_env.yield_star_array != null) {
                                env.yield_star_array = loop_env.yield_star_array;
                                env.yield_star_index = loop_env.yield_star_index;
                            }
                            env.yield_hit = true;
                            env.yield_value = loop_env.yield_value;
                            env.yield_caught_by_loop = true;
                            result = loop_env.yield_value;
                            loop_env.yield_hit = false;
                            break;
                        }
                        if (loop_env.return_hit) break;
                        if (loop_env.break_hit) {
                            consumeBreak(loop_env, fo_my_label);
                            env.for_of_gen = null;
                            break;
                        }
                if (loop_env.continue_hit) {
                    if (consumeContinue(loop_env, fo_my_label)) {
                        continue;
                    }
                    break;
                }
                    }
                },
                .iterator => |iter| {
                    while (true) {
                        const next_val = iter.next(env.allocator, &env.arrays, &env.objects);
                        if (next_val != .js_object) break;
                        const done_val = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                        const is_done = switch (done_val) {
                            .boolean => |b| b,
                            else => true,
                        };
                        if (is_done) break;
                        const val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
                        try setLoopVar(loop_env, f.kind, f.variable, val);
                        result = try evaluate(f.body, loop_env);
                        if (loop_env.yield_hit) {
                            if (loop_env.yield_star_gen != null) env.yield_star_gen = loop_env.yield_star_gen;
                            if (loop_env.yield_star_array != null) {
                                env.yield_star_array = loop_env.yield_star_array;
                                env.yield_star_index = loop_env.yield_star_index;
                            }
                            env.yield_hit = true;
                            env.yield_value = loop_env.yield_value;
                            env.yield_caught_by_loop = true;
                            result = loop_env.yield_value;
                            loop_env.yield_hit = false;
                            break;
                        }
                        if (loop_env.return_hit) break;
                if (loop_env.break_hit) {
                    consumeBreak(loop_env, fo_my_label);
                    break;
                }
                if (loop_env.continue_hit) {
                    if (consumeContinue(loop_env, fo_my_label)) {
                        continue;
                    }
                    break;
                }
                    }
                },
                else => {
                    return error.TypeError;
                },
            }

            return result;
        },
        .ForInLoop => |f| {
            var result: ast.Value = .{ .float = 0.0 };
            const fi_my_label = env.pending_loop_label;
            env.pending_loop_label = null;
            const object_val = try evaluate(f.object, env);

            var block_env_buf: Environment = undefined;
            const loop_env: *Environment = if (f.kind == .Let or f.kind == .Const) blk: {
                block_env_buf = try Environment.initBlock(env.allocator, env);
                break :blk &block_env_buf;
            } else env;
            defer if (f.kind == .Let or f.kind == .Const) block_env_buf.deinit();

            switch (object_val) {
                .js_object => |obj| {
                    // ES [[OwnPropertyKeys]] order: integer keys ascending, then
                    // string keys in insertion order (@@ internals skipped).
                    const ordered = obj.getForInKeys(env.allocator, &env.arrays) catch return error.OutOfMemory;
                    for (ordered.elements.items) |key_value| {
                        const key = key_value.string;
                        try setLoopVar(loop_env, f.kind, f.variable, .{ .string = key });
                        result = try evaluate(f.body, loop_env);
                        if (loop_env.return_hit) break;
                if (loop_env.break_hit) {
                    consumeBreak(loop_env, fi_my_label);
                    break;
                }
                if (loop_env.continue_hit) {
                    if (consumeContinue(loop_env, fi_my_label)) {
                        continue;
                    }
                    break;
                }
                    }
                },
                .array => |arr| {
                    var i: usize = 0;
                    while (i < arr.elements.items.len) {
                        var buf: [32]u8 = undefined;
                        const key_slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                        const key = try env.allocator.dupe(u8, key_slice);
                        env.owned_strings.append(env.allocator, key) catch {};
                        try setLoopVar(loop_env, f.kind, f.variable, .{ .string = key });
                        result = try evaluate(f.body, loop_env);
                        if (loop_env.return_hit) break;
                if (loop_env.break_hit) {
                    consumeBreak(loop_env, fi_my_label);
                    break;
                }
                        if (loop_env.continue_hit) {
                            if (consumeContinue(loop_env, fi_my_label)) {
                                i += 1;
                                continue;
                            }
                            break;
                        }
                        i += 1;
                    }
                },
                .string => |s| {
                    var i: usize = 0;
                    while (i < s.len) {
                        var buf: [32]u8 = undefined;
                        const key_slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                        const key = try env.allocator.dupe(u8, key_slice);
                        env.owned_strings.append(env.allocator, key) catch {};
                        try setLoopVar(loop_env, f.kind, f.variable, .{ .string = key });
                        result = try evaluate(f.body, loop_env);
                        if (loop_env.return_hit) break;
                if (loop_env.break_hit) {
                    consumeBreak(loop_env, fi_my_label);
                    break;
                }
                        if (loop_env.continue_hit) {
                            if (consumeContinue(loop_env, fi_my_label)) {
                                i += 1;
                                continue;
                            }
                            break;
                        }
                        i += 1;
                    }
                },
                .integer => |n| {
                    var repr: [32]u8 = undefined;
                    const str = std.fmt.bufPrint(&repr, "{d}", .{n}) catch "";
                    var i: usize = 0;
                    while (i < str.len) {
                        var buf: [4]u8 = undefined;
                        const key_slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                        const key = try env.allocator.dupe(u8, key_slice);
                        env.owned_strings.append(env.allocator, key) catch {};
                        try setLoopVar(loop_env, f.kind, f.variable, .{ .string = key });
                        result = try evaluate(f.body, loop_env);
                        if (loop_env.return_hit) break;
                if (loop_env.break_hit) {
                    consumeBreak(loop_env, fi_my_label);
                    break;
                }
                        if (loop_env.continue_hit) {
                            if (consumeContinue(loop_env, fi_my_label)) {
                                i += 1;
                                continue;
                            }
                            break;
                        }
                        i += 1;
                    }
                },
                .float => |n| {
                    var repr: [64]u8 = undefined;
                    const str = std.fmt.bufPrint(&repr, "{d}", .{n}) catch "";
                    var i: usize = 0;
                    while (i < str.len) {
                        var buf: [4]u8 = undefined;
                        const key_slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                        const key = try env.allocator.dupe(u8, key_slice);
                        env.owned_strings.append(env.allocator, key) catch {};
                        try setLoopVar(loop_env, f.kind, f.variable, .{ .string = key });
                        result = try evaluate(f.body, loop_env);
                        if (loop_env.return_hit) break;
                if (loop_env.break_hit) {
                    consumeBreak(loop_env, fi_my_label);
                    break;
                }
                        if (loop_env.continue_hit) {
                            if (consumeContinue(loop_env, fi_my_label)) {
                                i += 1;
                                continue;
                            }
                            break;
                        }
                        i += 1;
                    }
                },
                else => {},
            }

            return result;
        },
        .WhileLoop => |w| {
            if (try optimizations.optimizeArrayPushLoop(w, env)) |result| {
                return result;
            }

            if (try optimizations.optimizeSimpleWhileLoop(w, env)) |result| {
                return result;
            }

            var w_pre_limit: ?f64 = null;
            if (w.condition.* == .BinaryExpression) {
                const be = w.condition.BinaryExpression;
                if (be.left.* == .Identifier) {
                    w_pre_limit = switch (be.right.*) {
                        .FloatLiteral => |v| v.value,
                        .IntegerLiteral => |v| @floatFromInt(v.value),
                        else => null,
                    };
                    if (w_pre_limit == null) {
                        const val = evaluate(be.right, env) catch null;
                        if (val) |v| {
                            w_pre_limit = switch (v) {
                                .float => |fval| fval,
                                .integer => |ival| @floatFromInt(ival),
                                else => null,
                            };
                        }
                    }
                }
            }

            const w_loop_var: ?[]const u8 = if (w_pre_limit != null)
                if (w.condition.* == .BinaryExpression)
                    if (w.condition.BinaryExpression.left.* == .Identifier)
                        w.condition.BinaryExpression.left.Identifier.name
                    else
                        null
                else
                    null
            else
                null;

            var result: ast.Value = .{ .float = 0.0 };

            const w_my_label = env.pending_loop_label;
            env.pending_loop_label = null;
            while (true) {
                if (w_loop_var) |vn| {
                    const current_val = env.get(vn) orelse break;
                    const current_f: f64 = switch (current_val) {
                        .float => |v| v,
                        .integer => |v| @floatFromInt(v),
                        else => break,
                    };
                    if (w.condition.* == .BinaryExpression and w.condition.BinaryExpression.operator == .LessThanOrEqual) {
                        if (current_f > w_pre_limit.?) break;
                    } else {
                        if (current_f >= w_pre_limit.?) break;
                    }
                } else {
                    const cond_val = try evaluate(w.condition, env);
                    const is_false = switch (cond_val) {
                        .boolean => |bv| !bv,
                        .float => |fv| fv == 0.0,
                        .integer => |iv| iv == 0,
                        else => false,
                    };
                    if (is_false) break;
                }

                result = try evaluate(w.body, env);
                if (env.yield_hit) {
                    env.yield_caught_by_loop = true;
                    result = env.yield_value;
                    env.yield_hit = false;
                    break;
                }
                if (env.return_hit) break;
                if (env.break_hit) {
                    consumeBreak(env, w_my_label);
                    break;
                }
                if (env.continue_hit) {
                    if (consumeContinue(env, w_my_label)) {
                        continue;
                    }
                    break;
                }
            }

            return result;
        },
        .DoWhileLoop => |d| {
            var result: ast.Value = .{ .float = 0.0 };

            const d_my_label = env.pending_loop_label;
            env.pending_loop_label = null;
            while (true) {
                result = try evaluate(d.body, env);
                if (env.yield_hit) {
                    env.yield_caught_by_loop = true;
                    result = env.yield_value;
                    env.yield_hit = false;
                    break;
                }
                if (env.return_hit) break;
                if (env.break_hit) {
                    consumeBreak(env, d_my_label);
                    break;
                }

                // Reset continue_hit so it doesn't propagate to outer loops
                // Then evaluate condition to determine if loop continues
                if (env.continue_hit) {
                    if (!consumeContinue(env, d_my_label)) {
                        // Labeled continue for outer loop — propagate
                        break;
                    }
                }

                const cond_val = try evaluate(d.condition, env);
                const is_false = switch (cond_val) {
                    .boolean => |bv| !bv,
                    .float => |fv| fv == 0.0,
                    .integer => |iv| iv == 0,
                    else => false,
                };
                if (is_false) break;
            }

            return result;
        },
        .IfStatement => |i| {
            const cond_val = try evaluate(i.condition, env);
            const is_truthy = switch (cond_val) {
                .boolean => |b| b,
                .float => |f| f != 0.0,
                .integer => |iv| iv != 0,
                .string => |s| s.len > 0,
                .void => false,
                else => true,
            };

            if (is_truthy) {
                const result = try evaluate(i.consequence, env);
                return result;
            } else if (i.alternative) |alt| {
                const result = try evaluate(alt, env);
                return result;
            } else {
                return .{ .float = 0.0 };
            }
        },
        .ConditionalExpression => |c| {
            // Lazy evaluation: only evaluate the chosen branch.
            const cond_val = try evaluate(c.condition, env);
            const is_truthy = switch (cond_val) {
                .boolean => |b| b,
                .float => |f| f != 0.0,
                .integer => |iv| iv != 0,
                .string => |s| s.len > 0,
                .void => false,
                else => true,
            };
            if (is_truthy) {
                return try evaluate(c.consequent, env);
            } else {
                return try evaluate(c.alternate, env);
            }
        },
        .BreakStatement => |bs| {
            env.break_hit = true;
            env.break_label = bs.label;
            return .{ .void = {} };
        },
        .ContinueStatement => |cs| {
            env.continue_hit = true;
            env.continue_label = cs.label;
            return .{ .void = {} };
        },
        .LabeledStatement => |ls| {
            // Set pending_loop_label so the inner loop can capture it
            env.pending_loop_label = ls.label;
            const result = try evaluate(ls.body, env);
            // Consume labeled break targeting this label
            if (env.break_hit and env.break_label != null and
                std.mem.eql(u8, env.break_label.?, ls.label))
            {
                env.break_hit = false;
                env.break_label = null;
            }
            // Consume labeled continue targeting this label
            if (env.continue_hit and env.continue_label != null and
                std.mem.eql(u8, env.continue_label.?, ls.label))
            {
                // continue can only target iteration statements (loops)
                const is_loop = switch (ls.body.*) {
                    .ForLoop, .WhileLoop, .DoWhileLoop, .ForOfLoop, .ForInLoop => true,
                    else => false,
                };
                if (!is_loop) {
                    return error.InvalidContinueTarget;
                }
                env.continue_hit = false;
                env.continue_label = null;
            }
            return result;
        },
        .DeleteExpression => |d| {
            // delete operator: delete obj.prop, delete arr[idx]
            // In non-strict mode, delete always returns true
            switch (d.operand.*) {
                .MemberAccess => |m| {
                    const obj_val = try evaluate(m.object, env);
                    if (obj_val == .js_object) {
                        _ = obj_val.js_object.properties.remove(m.property);
                        if (env.globalObject()) |g| {
                            if (g == obj_val.js_object) env.removeGlobalProperty(m.property);
                        }
                    }
                    return .{ .boolean = true };
                },
                .ArrayIndex => |ai| {
                    const obj_val = try evaluate(ai.array, env);
                    const idx_val = try evaluate(ai.index, env);
                    if (obj_val == .js_object) {
                        const key = switch (idx_val) {
                            .string => |s| s,
                            .integer => |i| blk: {
                                var buf: [32]u8 = undefined;
                                const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                                const owned = try env.allocator.dupe(u8, s);
                                env.owned_strings.append(env.allocator, owned) catch {};
                                break :blk owned;
                            },
                            .float => |f| blk: {
                                var buf: [64]u8 = undefined;
                                const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.OutOfMemory;
                                const owned = try env.allocator.dupe(u8, s);
                                env.owned_strings.append(env.allocator, owned) catch {};
                                break :blk owned;
                            },
                            else => return error.InvalidIndex,
                        };
                        _ = obj_val.js_object.properties.remove(key);
                        if (env.globalObject()) |g| {
                            if (g == obj_val.js_object) env.removeGlobalProperty(key);
                        }
                    } else if (obj_val == .array) {
                        const index: i64 = switch (idx_val) {
                            .integer => |i| i,
                            .float => |f| @intFromFloat(f),
                            else => return error.InvalidIndex,
                        };
                        if (index >= 0) {
                            const uidx = @as(usize, @intCast(index));
                            if (uidx < obj_val.array.elements.items.len) {
                                obj_val.array.elements.items[uidx] = .{ .hole = {} };
                            }
                        }
                    }
                    return .{ .boolean = true };
                },
                else => {
                    // delete on identifier or other expression returns true (non-strict)
                    _ = try evaluate(d.operand, env);
                    return .{ .boolean = true };
                },
            }
        },
        .TypeOfExpression => |t| {
            // Only a bare identifier reference may be undeclared here; anything else
            // (typeof (x + 1), typeof a.b with a undeclared) must still throw.
            const val = if (t.operand.* == .Identifier)
                evaluate(t.operand, env) catch |err| {
                    if (err == error.UndefinedVariable) {
                        return .{ .string = "undefined" };
                    }
                    return err;
                }
            else
                try evaluate(t.operand, env);
            const type_str: []const u8 = switch (val) {
                .integer => "number",
                .float => "number",
                .big_int => "bigint",
                .string => "string",
                .boolean => "boolean",
                .void => "undefined",
                .null => "object",
                .array => "object",
                .js_object => if (objectPrototypeMod.isObjectPrototypeMethodStub(val) != null or functionMod.isBoundFunction(val.js_object) or isCallableValue(val)) "function" else "object",
                .function => "function",
                .closure => "function",
                .object => "object",
                .generator => "function",
                .symbol => "symbol",
                .iterator => "object",
                .hole => "undefined",
                .array_iterator => "object",
                .regexp => "object",
            };
            return .{ .string = type_str };
        },
        .ReturnStatement => |r| {
            env.return_hit = true;
            if (r.value) |val| {
                const v = try evaluate(val, env);
                return v;
            } else {
                return .{ .void = {} };
            }
        },
        .ThrowStatement => |ts| {
            const val = try evaluate(ts.value, env);
            env.throw_hit = true;
            env.throw_value = val;
            return val;
        },
        .TryCatchFinally => |tc| {
            var body_val: ast.Value = .{ .void = {} };
            var threw = false;
            if (evaluate(tc.body, env)) |val| {
                body_val = val;
            } else |_| {
                threw = true;
            }
            if (!threw) threw = env.throw_hit;
            if (!threw) {
                if (tc.finally_body) |fb| _ = try evaluate(fb, env);
                return body_val;
            }
            if (tc.catch_body) |cb| {
                const error_val: ast.Value = if (env.throw_hit) blk: {
                    const v = env.throw_value;
                    env.throw_hit = false;
                    env.throw_value = .{ .void = {} };
                    break :blk v;
                } else .{ .void = {} };
                if (tc.catch_param) |param| try env.setVar(param, error_val);
                var catch_val: ast.Value = .{ .void = {} };
                if (evaluate(cb, env)) |v| { catch_val = v; } else |_| {}
                if (tc.finally_body) |fb| _ = try evaluate(fb, env);
                return catch_val;
            }
            if (tc.finally_body) |fb| _ = try evaluate(fb, env);
            if (env.throw_hit) return env.throw_value;
            return error.PropagatedError;
        },
        .GeneratorDeclaration => |g| {
            try env.setFunction(g.name, node);
            return .{ .function = @ptrCast(node) };
        },
        .ClassDeclaration => |c| {
            const class_val = try createClassValue(env, node, c.name, c.superclass, c.methods, c.fields);
            try env.setLet(c.name, class_val);
            return class_val;
        },
        .ClassExpression => |c| {
            return try createClassValue(env, node, c.name, c.superclass, c.methods, c.fields);
        },
        .FunctionDeclaration => |f| {
            if (f.name.len > 0) try env.setFunction(f.name, node);
            // Capture the defining scope so calls keep reading/writing the
            // same bindings after the enclosing call returns.
            const scope = try env.captureEnv();
            return .{ .closure = try ast.ClosureValue.init(env.allocator, @ptrCast(@as(*anyopaque, node)), @ptrCast(scope)) };
        },
        .FunctionCall => |f| {
            if (std.mem.eql(u8, f.name, "super")) {
                var super_args = try evaluateArgs(f.arguments, env);
                defer super_args.deinit(env.allocator);
                return try invokeSuperConstructor(env, super_args.items);
            }
            const has_spread_args = blk: {
                var found = false;
                for (f.arguments) |arg| {
                    if (arg.* == .SpreadExpression) {
                        found = true;
                        break;
                    }
                }
                break :blk found;
            };

            if (env.getBuiltin(f.name)) |builtin_fn| {
                if (has_spread_args) {
                    var expanded = try evaluateArgs(f.arguments, env);
                    defer expanded.deinit(env.allocator);
                    const result = builtin_fn(expanded.items, env);
                    if (env.throw_hit) return error.Thrown;
                    return switch (result) {
                        .value => |val| val,
                        .void => .{ .float = 0.0 },
                    };
                }
                var stack_buf: [16]ast.Value = undefined;
                const total = f.arguments.len;
                if (total <= 16) {
                    for (f.arguments, 0..) |arg, idx| {
                        stack_buf[idx] = try evaluate(arg, env);
                    }
                    const result = builtin_fn(stack_buf[0..total], env);
                    if (env.throw_hit) return error.Thrown;
                    return switch (result) {
                        .value => |val| val,
                        .void => .{ .float = 0.0 },
                    };
                }
                var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                defer args.deinit(env.allocator);
                for (f.arguments) |arg| {
                    const val = try evaluate(arg, env);
                    try args.append(env.allocator, val);
                }
                const result = builtin_fn(args.items, env);
                args.clearAndFree(env.allocator);
                if (env.throw_hit) return error.Thrown;
                return switch (result) {
                    .value => |val| val,
                    .void => .{ .float = 0.0 },
                };
            }

            if (env.getFunctionWithModuleFallback(f.name) == null) {
                if (env.get(f.name)) |val| {
                    if (val == .closure) {
                        var closed_args = try evaluateArgs(f.arguments, env);
                        defer closed_args.deinit(env.allocator);
                        return try callFunctionValue(val, closed_args.items, env, ast.Value{ .void = {} });
                    }
                    if (val == .js_object and functionMod.isBoundFunction(val.js_object)) {
                        var bound_call_args = try evaluateArgs(f.arguments, env);
                        defer bound_call_args.deinit(env.allocator);
                        return try invokeBoundFunction(val.js_object, bound_call_args.items, env);
                    }
                    if (val == .js_object and promiseMod.isResolver(val)) {
                        var resolver_args = try evaluateArgs(f.arguments, env);
                        defer resolver_args.deinit(env.allocator);
                        promiseMod.callResolver(env, val.js_object, resolver_args.items);
                        return .{ .void = {} };
                    }
                }
            }

            const func_node = env.getFunctionWithModuleFallback(f.name) orelse blk: {
                // Not a named function — try variable value (e.g. anonymous function passed as arg)
                const val = env.get(f.name) orelse return error.UndefinedFunction;
                switch (val) {
                    .function => |fn_ptr| break :blk @as(*ast.Node, @alignCast(@ptrCast(fn_ptr))),
                    .generator => |gen| {
                        // Evaluate args for side effects, then return the generator
                        for (f.arguments) |arg| {
                            _ = try evaluate(arg, env);
                        }
                        return .{ .generator = gen };
                    },
                    else => return error.NotAFunction,
                }
            };

            // Invoke the function via the shared helper
            const fc_this = ast.Value{ .void = {} };
            if (has_spread_args) {
                var expanded = try evaluateArgs(f.arguments, env);
                defer expanded.deinit(env.allocator);
                return try invokeFunctionNode(func_node, expanded.items, env, fc_this);
            }
            var fc_stack: [16]ast.Value = undefined;
            const fc_total = f.arguments.len;
            if (fc_total <= 16) {
                for (f.arguments, 0..) |arg, idx| {
                    fc_stack[idx] = try evaluate(arg, env);
                }
                return try invokeFunctionNode(func_node, fc_stack[0..fc_total], env, fc_this);
            }
            {
                var fc_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, fc_total);
                defer fc_args.deinit(env.allocator);
                for (f.arguments) |arg| {
                    try fc_args.append(env.allocator, try evaluate(arg, env));
                }
                return try invokeFunctionNode(func_node, fc_args.items, env, fc_this);
            }
        },
        .ArrowFunction => {
            const scope = try env.captureEnv();
            return .{ .closure = try ast.ClosureValue.init(env.allocator, @ptrCast(@as(*anyopaque, node)), @ptrCast(scope)) };
        },
        .NewExpression => |ne| {
            const func_name = switch (ne.callee.*) {
                .Identifier => |id| id.name,
                else => return error.InvalidCallee,
            };

            if (std.mem.eql(u8, func_name, "Promise")) {
                var promise_args = try evaluateArgs(ne.arguments, env);
                defer promise_args.deinit(env.allocator);
                return try constructPromise(env, promise_args.items);
            }

            if (env.get(func_name)) |callee_val| {
                if (callee_val == .js_object and callee_val.js_object.properties.get("@@class") != null) {
                    var class_args = try evaluateArgs(ne.arguments, env);
                    defer class_args.deinit(env.allocator);
                    return try constructClass(env, callee_val, class_args.items);
                }
            }

            const has_spread_args = blk: {
                var found = false;
                for (ne.arguments) |arg| {
                    if (arg.* == .SpreadExpression) {
                        found = true;
                        break;
                    }
                }
                break :blk found;
            };

            if (env.getBuiltin(func_name)) |builtin_fn| {
            const is_boolean_ctor = std.mem.eql(u8, func_name, "Boolean");
                if (has_spread_args) {
                    var expanded = try evaluateArgs(ne.arguments, env);
                    defer expanded.deinit(env.allocator);
                    const result = builtin_fn(expanded.items, env);
                    if (env.throw_hit) return error.Thrown;
                    return switch (result) {
                        .value => |val| if (is_boolean_ctor) (try booleanMod.makeBooleanWrapper(env, val)) orelse val else val,
                        .void => .{ .float = 0.0 },
                    };
                }
                var stack_buf: [16]ast.Value = undefined;
                const total = ne.arguments.len;
                if (total <= 16) {
                    for (ne.arguments, 0..) |arg, idx| {
                        stack_buf[idx] = try evaluate(arg, env);
                    }
                    const result = builtin_fn(stack_buf[0..total], env);
                    if (env.throw_hit) return error.Thrown;
                    return switch (result) {
                        .value => |val| if (is_boolean_ctor) (try booleanMod.makeBooleanWrapper(env, val)) orelse val else val,
                        .void => .{ .float = 0.0 },
                    };
                }
                var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                defer args.deinit(env.allocator);
                for (ne.arguments) |arg| {
                    const val = try evaluate(arg, env);
                    try args.append(env.allocator, val);
                }
                const result = builtin_fn(args.items, env);
                args.clearAndFree(env.allocator);
                if (env.throw_hit) return error.Thrown;
                return switch (result) {
                    .value => |val| if (is_boolean_ctor) (try booleanMod.makeBooleanWrapper(env, val)) orelse val else val,
                    .void => .{ .float = 0.0 },
                };
            }

            const func_node = env.getFunctionWithModuleFallback(func_name) orelse return error.UndefinedFunction;

            // Create 'this' object for constructor calls
            const new_obj = try ast.ObjectValue.init(env.allocator);
            try env.objects.append(env.allocator, new_obj);
            const ne_this = ast.Value{ .js_object = new_obj };

            const checkResult = struct {
                fn check(r: ast.Value, t: ast.Value) ast.Value {
                    return switch (r) {
                        .void, .null, .boolean, .integer, .float, .string => t,
                        else => r,
                    };
                }
            }.check;

            if (has_spread_args) {
                var expanded = try evaluateArgs(ne.arguments, env);
                defer expanded.deinit(env.allocator);
                return checkResult(try invokeFunctionNode(func_node, expanded.items, env, ne_this), ne_this);
            }
            var ne_stack: [16]ast.Value = undefined;
            const ne_total = ne.arguments.len;
            if (ne_total <= 16) {
                for (ne.arguments, 0..) |arg, idx| {
                    ne_stack[idx] = try evaluate(arg, env);
                }
                return checkResult(try invokeFunctionNode(func_node, ne_stack[0..ne_total], env, ne_this), ne_this);
            }
            {
                var ne_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, ne_total);
                defer ne_args.deinit(env.allocator);
                for (ne.arguments) |arg| {
                    try ne_args.append(env.allocator, try evaluate(arg, env));
                }
                return checkResult(try invokeFunctionNode(func_node, ne_args.items, env, ne_this), ne_this);
            }
        },
                .UsingDeclaration => |v| {
            if (v.value) |val_expr| {
                _ = try evaluate(val_expr, env);
            }
            return .{ .void = {} };
        },
        .VoidExpression => |v| {
            _ = try evaluate(v.operand, env);
            return .{ .void = {} };
        },
        .EmptyStatement => return .{ .void = {} },
        .SwitchStatement => |s| {
            const disc = try evaluate(s.discriminant, env);

            // First pass: evaluate case tests in source order until one matches
            // (tests after the matching case are not evaluated). `default` only
            // records its position; later cases are still tested.
            var start: ?usize = null;
            var default_idx: ?usize = null;
            for (s.cases, 0..) |case_node, i| {
                if (start != null) break;
                if (case_node.* != .SwitchCase) continue;
                const sc = case_node.SwitchCase;
                if (sc.test_expr) |te| {
                    const test_val = try evaluate(te, env);
                    if (valuesEqual(disc, test_val)) start = i;
                } else {
                    default_idx = i;
                }
            }

            const begin = start orelse default_idx orelse return .{ .void = {} };
            const my_label = env.pending_loop_label;
            env.pending_loop_label = null;

            var result: ast.Value = .{ .void = {} };
            var i = begin;
            while (i < s.cases.len) : (i += 1) {
                const case_node = s.cases[i];
                if (case_node.* != .SwitchCase) continue;
                result = try evaluate(case_node.SwitchCase.consequent, env);
                if (env.yield_hit) break;
                if (env.return_hit) break;
                if (env.break_hit) {
                    const matches = (env.break_label == null) or
                        (my_label != null and std.mem.eql(u8, env.break_label.?, my_label.?));
                    if (matches) {
                        env.break_hit = false;
                        env.break_label = null;
                    }
                    break;
                }
                if (env.continue_hit) break;
            }
            return result;
        },
        .SwitchCase => return .{ .void = {} },
        .ImportMetaExpression => {
            const obj = try ast.ObjectValue.init(env.allocator);
            try env.objects.append(env.allocator, obj);
            // Populate import.meta.url with the module's file path
            const url = if (env.module_dir) |dir| blk: {
                var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch break :blk "";
                buf.appendSlice(env.allocator, "file://") catch {};
                buf.appendSlice(env.allocator, dir) catch {};
                const s = buf.toOwnedSlice(env.allocator) catch break :blk "";
                env.owned_strings.append(env.allocator, s) catch {};
                break :blk s;
            } else "file:///module";
            if (url.len > 0) {
                try obj.properties.put("url", .{ .string = url });
            }
            // import.meta.resolve is a stub function
            const resolve_buf = try env.allocator.create(ast.Node);

            env.synthetic_asts.append(env.allocator, resolve_buf) catch {};
            resolve_buf.* = .{ .ArrowFunction = .{
                .parameters = try env.allocator.dupe([]const u8, &.{"specifier"}),
                .body = try env.allocator.create(ast.Node),
            } };
            resolve_buf.ArrowFunction.body.* = .{ .StringLiteral = .{ .value = "file:///resolved" } };
            try obj.properties.put("resolve", .{ .function = @ptrCast(resolve_buf) });
            return .{ .js_object = obj };
        },
        .DynamicImportExpression => return .{ .js_object = try ast.ObjectValue.init(env.allocator) },
        .DirectCall => |dc| {
            const callee_val = try evaluate(dc.callee, env);
            if (callee_val == .generator) {
                // Evaluate args for side effects, then return the generator
                for (dc.arguments) |arg| {
                    _ = try evaluate(arg, env);
                }
                return callee_val;
            }
            if (callee_val == .iterator) {
                // arr[Symbol.iterator]() yields the iterator itself.
                for (dc.arguments) |arg| {
                    _ = try evaluate(arg, env);
                }
                return callee_val;
            }
            if (callee_val == .closure) {
                var expanded = try evaluateArgs(dc.arguments, env);
                defer expanded.deinit(env.allocator);
                return try callFunctionValue(callee_val, expanded.items, env, ast.Value{ .void = {} });
            }
            if (callee_val == .js_object and functionMod.isBoundFunction(callee_val.js_object)) {
                var expanded = try evaluateArgs(dc.arguments, env);
                defer expanded.deinit(env.allocator);
                return try invokeBoundFunction(callee_val.js_object, expanded.items, env);
            }
            if (callee_val != .function) {
                return error.NotAFunction;
            }
            const func_node: *ast.Node = @alignCast(@ptrCast(callee_val.function));

            const has_spread_args = blk: {
                var found = false;
                for (dc.arguments) |arg| {
                    if (arg.* == .SpreadExpression) {
                        found = true;
                        break;
                    }
                }
                break :blk found;
            };

            const dc_this = ast.Value{ .void = {} };
            if (has_spread_args) {
                var expanded = try evaluateArgs(dc.arguments, env);
                defer expanded.deinit(env.allocator);
                return try invokeFunctionNode(func_node, expanded.items, env, dc_this);
            }
            var dc_stack: [16]ast.Value = undefined;
            const dc_total = dc.arguments.len;
            if (dc_total <= 16) {
                for (dc.arguments, 0..) |arg, idx| {
                    dc_stack[idx] = try evaluate(arg, env);
                }
                return try invokeFunctionNode(func_node, dc_stack[0..dc_total], env, dc_this);
            }
            {
                var dc_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, dc_total);
                defer dc_args.deinit(env.allocator);
                for (dc.arguments) |arg| {
                    try dc_args.append(env.allocator, try evaluate(arg, env));
                }
                return try invokeFunctionNode(func_node, dc_args.items, env, dc_this);
            }
        },
        .OptionalChain => |oc| {
            var current: ast.Value = .{ .void = {} };
            var receiver: ?ast.Value = null;
            var method_name: []const u8 = "";
            switch (oc.base.*) {
                .MemberAccess => |m| {
                    receiver = try evaluate(m.object, env);
                    method_name = m.property;
                    current = try ocMember(receiver.?, m.property, env);
                },
                .ArrayIndex => |a| {
                    const idx = try evaluate(a.index, env);
                    receiver = try evaluate(a.array, env);
                    current = try ocIndex(receiver.?, idx, env);
                },
                else => current = try evaluate(oc.base, env),
            }
            for (oc.links) |link| {
                if (link.optional and ocIsNullish(current)) {
                    return .{ .void = {} };
                }
                switch (link.kind) {
                    .property => {
                        receiver = current;
                        method_name = link.name;
                        current = try ocMember(current, link.name, env);
                    },
                    .index => {
                        const idx = try evaluate(link.expr.?, env);
                        receiver = current;
                        method_name = "";
                        current = try ocIndex(current, idx, env);
                    },
                    .call => {
                        var args = try evaluateArgs(link.arguments, env);
                        defer args.deinit(env.allocator);
                        current = try ocCall(current, receiver, args.items, env, method_name);
                    },
                }
            }
            return current;
        },
        .MemberAccess => |m| {
            if (m.object.* == .Identifier and std.mem.eql(u8, m.object.Identifier.name, "super")) {
                return try getSuperProperty(env, m.property);
            }
            const value = try evaluate(m.object, env);

            if (value == .array) {
                if (std.mem.eql(u8, m.property, "length")) {
                    return .{ .integer = @intCast(value.array.elements.items.len) };
                }

                const builtin_obj = env.getBuiltinObject("Array") orelse {
                    return error.UndefinedObject;
                };

                if (builtin_obj.getMethod(m.property)) |_| {
                    return .{ .object = @ptrCast(builtin_obj) };
                } else {
                    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.property}) catch {
                        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
                        return error.Thrown;
                    };
                    defer env.allocator.free(_msg);
                    _ = throwError(env, "TypeError", .{ .string = _msg });
                    return error.Thrown;
                }
            } else if (value == .iterator) {
                return .{ .void = {} };
            } else if (value == .regexp) {
                return regexpMod.getProperty(value.regexp, m.property);
            } else if (value == .js_object) {
                var cur: ?*ast.ObjectValue = value.js_object;
                while (cur) |o| {
                    if (o.properties.get(m.property)) |v| {
                        if (accessorPart(v, "get")) |getter| {
                            return try callFunctionValue(getter, &[_]ast.Value{}, env, .{ .js_object = value.js_object });
                        }
                        if (isAccessorValue(v)) return .{ .void = {} };
                        return v;
                    }
                    cur = o.prototype;
                }
                return .{ .void = {} };
            } else if (value == .object) {
                const bObjPtr: *const builtinsTypes.BuiltinObjectImpl = @ptrCast(@alignCast(value.object));
                if (bObjPtr.getProperty(m.property)) |prop_val| return prop_val;
                return .{ .void = {} };
            } else {
                return error.InvalidMemberAccess;
            }
        },
        .MethodCall => |m| {
            if (m.object.* == .Identifier and std.mem.eql(u8, m.object.Identifier.name, "super")) {
                var super_args = try evaluateArgs(m.arguments, env);
                defer super_args.deinit(env.allocator);
                return try callSuperMethod(env, m.method, super_args.items);
            }
            const has_spread_args = blk: {
                var found = false;
                for (m.arguments) |arg| {
                    if (arg.* == .SpreadExpression) {
                        found = true;
                        break;
                    }
                }
                break :blk found;
            };

            var expanded_method_args: ?std.ArrayList(ast.Value) = null;
            defer if (expanded_method_args) |*ema| ema.deinit(env.allocator);

            if (has_spread_args) {
                expanded_method_args = try evaluateArgs(m.arguments, env);
            }

            if (!has_spread_args and isFunctionProtoMethod(m.method)) {
                if (functionProtoReceiver(env, m.object)) |recv| {
                    if ((recv == .function or recv == .closure or recv == .generator or (recv == .js_object and functionMod.isBoundFunction(recv.js_object)))) {
                        return try evaluateFunctionPrototypeMethod(m.method, recv, m.arguments, env);
                    }
                }
            }

            if (m.object.* == .Identifier) {
                if (env.get(m.object.Identifier.name)) |recv| {
                    if (recv == .regexp) return try callRegExpMethod(recv, m.method, m.arguments, env);
                }
            }

            if (m.object.* == .Identifier) {
                const obj_name = m.object.Identifier.name;

                if (env.get(obj_name)) |value| {
                    if (value == .array) {
                        if (expanded_method_args) |ema| {
                            var ma = try std.ArrayList(ast.Value).initCapacity(env.allocator, 1 + ema.items.len);
                            defer ma.deinit(env.allocator);
                            try ma.append(env.allocator, value);
                            try ma.appendSlice(env.allocator, ema.items);
                            const arr_builtin = env.getBuiltinObject("Array") orelse return error.UndefinedObject;
                            const method_fn = arr_builtin.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                            const result = method_fn(ma.items, env);
                            if (env.throw_hit) return error.Thrown;
                            return switch (result) {
                                .value => |val| val,
                                .void => .void,
                            };
                        }
                        var stack_buf: [16]ast.Value = undefined;
                        stack_buf[0] = value;
                        const total = 1 + m.arguments.len;
                        if (total <= 16) {
                            for (m.arguments, 0..) |arg, idx| {
                                stack_buf[idx + 1] = try evaluate(arg, env);
                            }
                            const arr_builtin = env.getBuiltinObject("Array") orelse return error.UndefinedObject;
                            const method_fn = arr_builtin.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                            const result = method_fn(stack_buf[0..total], env);
                            if (env.throw_hit) return error.Thrown;
                            return switch (result) {
                                .value => |val| val,
                                .void => .void,
                            };
                        }
                        var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, total);
                        defer method_args.deinit(env.allocator);
                        try method_args.append(env.allocator, value);
                        for (m.arguments) |arg| {
                            const val = try evaluate(arg, env);
                            try method_args.append(env.allocator, val);
                        }
                        const arr_builtin2 = env.getBuiltinObject("Array") orelse return error.UndefinedObject;
                        const method_fn2 = arr_builtin2.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                        const result2 = method_fn2(method_args.items, env);
                        if (env.throw_hit) return error.Thrown;
                        return switch (result2) {
                            .value => |val| val,
                            .void => .void,
                        };
                    } else if (value == .string) {
                        if (expanded_method_args) |ema| {
                            var ma = try std.ArrayList(ast.Value).initCapacity(env.allocator, 1 + ema.items.len);
                            defer ma.deinit(env.allocator);
                            try ma.append(env.allocator, value);
                            try ma.appendSlice(env.allocator, ema.items);
                            const str_builtin = env.getBuiltinObject("String") orelse return error.UndefinedObject;
                            const method_fn = str_builtin.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                            const result = method_fn(ma.items, env);
                            if (env.throw_hit) return error.Thrown;
                            return switch (result) {
                                .value => |val| val,
                                .void => .void,
                            };
                        }
                        var stack_buf: [16]ast.Value = undefined;
                        stack_buf[0] = value;
                        const total = 1 + m.arguments.len;
                        if (total <= 16) {
                            for (m.arguments, 0..) |arg, idx| {
                                stack_buf[idx + 1] = try evaluate(arg, env);
                            }
                            const str_builtin = env.getBuiltinObject("String") orelse return error.UndefinedObject;
                            const method_fn = str_builtin.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                            const result = method_fn(stack_buf[0..total], env);
                            if (env.throw_hit) return error.Thrown;
                            return switch (result) {
                                .value => |val| val,
                                .void => .void,
                            };
                        }
                        var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, total);
                        defer method_args.deinit(env.allocator);
                        try method_args.append(env.allocator, value);
                        for (m.arguments) |arg| {
                            const val = try evaluate(arg, env);
                            try method_args.append(env.allocator, val);
                        }
                        const str_builtin2 = env.getBuiltinObject("String") orelse return error.UndefinedObject;
                        const method_fn2 = str_builtin2.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                        const result2 = method_fn2(method_args.items, env);
                        if (env.throw_hit) return error.Thrown;
                        return switch (result2) {
                            .value => |val| val,
                            .void => .void,
                        };
                    } else if (value == .integer or value == .float) {
                        if (expanded_method_args) |ema| {
                            var ma = try std.ArrayList(ast.Value).initCapacity(env.allocator, 1 + ema.items.len);
                            defer ma.deinit(env.allocator);
                            try ma.append(env.allocator, value);
                            try ma.appendSlice(env.allocator, ema.items);
                            const num_builtin = env.getBuiltinObject("Number") orelse return error.UndefinedObject;
                            const method_fn = num_builtin.getMethod(m.method) orelse {
                                const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
                                    _ = throwError(env, "TypeError", .{ .string = "is not a function" });
                                    return error.Thrown;
                                };
                                defer env.allocator.free(_msg);
                                _ = throwError(env, "TypeError", .{ .string = _msg });
                                return error.Thrown;
                            };
                            const result = method_fn(ma.items, env);
                            if (env.throw_hit) return error.Thrown;
                            return switch (result) {
                                .value => |val| val,
                                .void => .{ .void = {} },
                            };
                        }
                        var stack_buf: [16]ast.Value = undefined;
                        stack_buf[0] = value;
                        const total = 1 + m.arguments.len;
                        if (total <= 16) {
                            for (m.arguments, 0..) |arg, i| {
                                stack_buf[1 + i] = try evaluate(arg, env);
                            }
                            const num_builtin2 = env.getBuiltinObject("Number") orelse return error.UndefinedObject;
                            const method_fn2 = num_builtin2.getMethod(m.method) orelse {
                                const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
                                    _ = throwError(env, "TypeError", .{ .string = "is not a function" });
                                    return error.Thrown;
                                };
                                defer env.allocator.free(_msg);
                                _ = throwError(env, "TypeError", .{ .string = _msg });
                                return error.Thrown;
                            };
                            const result2 = method_fn2(stack_buf[0..total], env);
                            if (env.throw_hit) return error.Thrown;
                            return switch (result2) {
                                .value => |val| val,
                                .void => .{ .void = {} },
                            };
                        }
                        var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, total);
                        defer method_args.deinit(env.allocator);
                        try method_args.append(env.allocator, value);
                        for (m.arguments) |arg| {
                            const val = try evaluate(arg, env);
                            try method_args.append(env.allocator, val);
                        }
                        const num_builtin3 = env.getBuiltinObject("Number") orelse return error.UndefinedObject;
                        const method_fn3 = num_builtin3.getMethod(m.method) orelse {
                            const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
                                _ = throwError(env, "TypeError", .{ .string = "is not a function" });
                                return error.Thrown;
                            };
                            defer env.allocator.free(_msg);
                            _ = throwError(env, "TypeError", .{ .string = _msg });
                            return error.Thrown;
                        };
                        const result3 = method_fn3(method_args.items, env);
                        if (env.throw_hit) return error.Thrown;
                        return switch (result3) {
                            .value => |val| val,
                            .void => .{ .void = {} },
                        };
                    } else if (value == .iterator) {
                        if (std.mem.eql(u8, m.method, "next")) {
                            return value.iterator.next(env.allocator, &env.arrays, &env.objects);
                        }
                        return .{ .void = {} };
                    } else if (value == .generator) {
                        if (std.mem.eql(u8, m.method, "next")) {
                            return try evaluateGeneratorNext(value.generator, env);
                        } else if (std.mem.eql(u8, m.method, "return")) {
                            var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, m.arguments.len);
                            defer method_args.deinit(env.allocator);
                            for (m.arguments) |arg| {
                                try method_args.append(env.allocator, try evaluate(arg, env));
                            }
                            return try evaluateGeneratorReturn(value.generator, env, method_args.items);
                        } else if (std.mem.eql(u8, m.method, "throw")) {
                            var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, m.arguments.len);
                            defer method_args.deinit(env.allocator);
                            for (m.arguments) |arg| {
                                try method_args.append(env.allocator, try evaluate(arg, env));
                            }
                            return try evaluateGeneratorThrow(value.generator, env, method_args.items);
                        }
                        return .{ .void = {} };
                    } else if (value == .js_object) {
                        if (findPropertyInChain(value.js_object, m.method)) |method_val| {
                            if (accessorPart(method_val, "get")) |getter| {
                                return try callFunctionValue(getter, &[_]ast.Value{}, env, value);
                            }
                            if (isAccessorValue(method_val)) return .{ .void = {} };
                            var js_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, m.arguments.len);
                            defer js_args.deinit(env.allocator);
                            for (m.arguments) |arg| {
                                try js_args.append(env.allocator, try evaluate(arg, env));
                            }
                            return try callFunctionValue(method_val, js_args.items, env, value);
                        }
                        if (value.js_object.properties.get("@@type")) |type_val| {
                            if (type_val == .string) {
                                const builtin_obj = env.getBuiltinObject(type_val.string) orelse return .{ .void = {} };
                                const method_fn = builtin_obj.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                                if (expanded_method_args) |ema| {
                                    var ma = try std.ArrayList(ast.Value).initCapacity(env.allocator, 1 + ema.items.len);
                                    defer ma.deinit(env.allocator);
                                    try ma.append(env.allocator, value);
                                    try ma.appendSlice(env.allocator, ema.items);
                                    const result = method_fn(ma.items, env);
                                    if (env.throw_hit) return error.Thrown;
                                    return switch (result) {
                                        .value => |val| val,
                                        .void => .void,
                                    };
                                }
                                var stack_buf: [16]ast.Value = undefined;
                                stack_buf[0] = value;
                                const total = 1 + m.arguments.len;
                                if (total <= 16) {
                                    for (m.arguments, 0..) |arg, idx| {
                                        stack_buf[idx + 1] = try evaluate(arg, env);
                                    }
                                    const result = method_fn(stack_buf[0..total], env);
                                    if (env.throw_hit) return error.Thrown;
                                    return switch (result) {
                                        .value => |val| val,
                                        .void => .void,
                                    };
                                }
                                var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, total);
                                defer method_args.deinit(env.allocator);
                                try method_args.append(env.allocator, value);
                                for (m.arguments) |arg| {
                                    const val = try evaluate(arg, env);
                                    try method_args.append(env.allocator, val);
                                }
                                const result = method_fn(method_args.items, env);
                                if (env.throw_hit) return error.Thrown;
                                return switch (result) {
                                    .value => |val| val,
                                    .void => .void,
                                };
                            }
                        }
                        return .{ .void = {} };
                    }
                }

                const builtin_obj = env.getBuiltinObject(obj_name) orelse {
                    return error.UndefinedObject;
                };
                const method = builtin_obj.getMethod(m.method) orelse {
                    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
                        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
                        return error.Thrown;
                    };
                    defer env.allocator.free(_msg);
                    _ = throwError(env, "TypeError", .{ .string = _msg });
                    return error.Thrown;
                };
                if (expanded_method_args) |ema| {
                    const result = method(ema.items, env);
                    if (env.throw_hit) return error.Thrown;
                    return switch (result) {
                        .value => |val| val,
                        .void => .void,
                    };
                }
                var stack_buf2: [16]ast.Value = undefined;
                const total2 = m.arguments.len;
                if (total2 <= 16) {
                    for (m.arguments, 0..) |arg, idx| {
                        stack_buf2[idx] = try evaluate(arg, env);
                    }
                    const result = method(stack_buf2[0..total2], env);
                    if (env.throw_hit) return error.Thrown;
                    return switch (result) {
                        .value => |val| val,
                        .void => .void,
                    };
                }
                var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                defer args.deinit(env.allocator);
                for (m.arguments) |arg| {
                    const val = try evaluate(arg, env);
                    try args.append(env.allocator, val);
                }
                const result = method(args.items, env);
                args.clearAndFree(env.allocator);
                if (env.throw_hit) return error.Thrown;
                return switch (result) {
                    .value => |val| val,
                    .void => .void,
                };
            }

            const value = try evaluate(m.object, env);
            if (value == .array) {
                if (expanded_method_args) |ema| {
                    var ma = try std.ArrayList(ast.Value).initCapacity(env.allocator, 1 + ema.items.len);
                    defer ma.deinit(env.allocator);
                    try ma.append(env.allocator, value);
                    try ma.appendSlice(env.allocator, ema.items);
                    const arr_obj = env.getBuiltinObject("Array") orelse return error.UndefinedObject;
                    const method_fn = arr_obj.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                    const result = method_fn(ma.items, env);
                    if (env.throw_hit) return error.Thrown;
                    return switch (result) {
                        .value => |val| val,
                        .void => .void,
                    };
                }
                var stack_buf3: [16]ast.Value = undefined;
                stack_buf3[0] = value;
                const total3 = 1 + m.arguments.len;
                if (total3 <= 16) {
                    for (m.arguments, 0..) |arg, idx| {
                        stack_buf3[idx + 1] = try evaluate(arg, env);
                    }
                    const arr_obj3 = env.getBuiltinObject("Array") orelse return error.UndefinedObject;
                    const method_fn3 = arr_obj3.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                    const result3 = method_fn3(stack_buf3[0..total3], env);
                    if (env.throw_hit) return error.Thrown;
                    return switch (result3) {
                        .value => |val| val,
                        .void => .void,
                    };
                }
                var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, total3);
                defer method_args.deinit(env.allocator);
                try method_args.append(env.allocator, value);
                for (m.arguments) |arg| {
                    const val = try evaluate(arg, env);
                    try method_args.append(env.allocator, val);
                }
                const arr_obj4 = env.getBuiltinObject("Array") orelse return error.UndefinedObject;
                const method_fn4 = arr_obj4.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                const result4 = method_fn4(method_args.items, env);
                if (env.throw_hit) return error.Thrown;
                return switch (result4) {
                    .value => |val| val,
                    .void => .void,
                };
            } else if (value == .iterator) {
                if (std.mem.eql(u8, m.method, "next")) {
                    return value.iterator.next(env.allocator, &env.arrays, &env.objects);
                }
                return .{ .void = {} };
            } else if (value == .regexp) {
                return try callRegExpMethod(value, m.method, m.arguments, env);
            } else if (value == .generator) {
                if (std.mem.eql(u8, m.method, "next")) {
                    return try evaluateGeneratorNext(value.generator, env);
                } else if (std.mem.eql(u8, m.method, "return")) {
                    var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, m.arguments.len);
                    defer method_args.deinit(env.allocator);
                    for (m.arguments) |arg| {
                        try method_args.append(env.allocator, try evaluate(arg, env));
                    }
                    return try evaluateGeneratorReturn(value.generator, env, method_args.items);
                } else if (std.mem.eql(u8, m.method, "throw")) {
                    var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, m.arguments.len);
                    defer method_args.deinit(env.allocator);
                    for (m.arguments) |arg| {
                        try method_args.append(env.allocator, try evaluate(arg, env));
                    }
                    return try evaluateGeneratorThrow(value.generator, env, method_args.items);
                }
                return .{ .void = {} };
            } else if (value == .js_object) {
                if (findPropertyInChain(value.js_object, m.method)) |method_val| {
                    if (accessorPart(method_val, "get")) |getter| {
                        return try callFunctionValue(getter, &[_]ast.Value{}, env, value);
                    }
                    if (isAccessorValue(method_val)) return .{ .void = {} };
                    var js_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, m.arguments.len);
                    defer js_args.deinit(env.allocator);
                    for (m.arguments) |arg| {
                        try js_args.append(env.allocator, try evaluate(arg, env));
                    }
                    return try callFunctionValue(method_val, js_args.items, env, value);
                }
                // Wrapper objects (Boolean, Number, String, ...) expose their
                // prototype methods through the builtin object registry.
                if (value.js_object.properties.get("@@type")) |tt| {
                    if (tt == .string and m.arguments.len + 1 <= 16) {
                        if (env.getBuiltinObject(tt.string)) |bObj| {
                            if (bObj.getMethod(m.method)) |md| {
                                var wrap_args: [16]ast.Value = undefined;
                                wrap_args[0] = value;
                                for (m.arguments, 0..) |arg, idx| {
                                    wrap_args[idx + 1] = try evaluate(arg, env);
                                }
                                const wrap_res = md(wrap_args[0 .. m.arguments.len + 1], env);
                                return switch (wrap_res) {
                                    .value => |val| val,
                                    .void => .{ .void = {} },
                                };
                            }
                        }
                    }
                }
                return .{ .void = {} };
            } else if (value == .object) {
                const bObjPtr: *const builtinsTypes.BuiltinObjectImpl = @ptrCast(@alignCast(value.object));
                const method = bObjPtr.getMethod(m.method) orelse {
                    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
                        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
                        return error.Thrown;
                    };
                    defer env.allocator.free(_msg);
                    _ = throwError(env, "TypeError", .{ .string = _msg });
                    return error.Thrown;
                };
                var stack_buf4: [16]ast.Value = undefined;
                var args4: []ast.Value = &[_]ast.Value{};
                if (m.arguments.len > 0) {
                    if (m.arguments.len <= 16) {
                        for (m.arguments, 0..) |arg, idx| {
                            stack_buf4[idx] = try evaluate(arg, env);
                        }
                        args4 = stack_buf4[0..m.arguments.len];
                    }
                }
                const result4 = method(args4, env);
                if (env.throw_hit) return error.Thrown;
                return switch (result4) {
                    .value => |val| val,
                    .void => .void,
                };
            } else if (value == .string) {
                if (expanded_method_args) |ema| {
                    var ma = try std.ArrayList(ast.Value).initCapacity(env.allocator, 1 + ema.items.len);
                    defer ma.deinit(env.allocator);
                    try ma.append(env.allocator, value);
                    try ma.appendSlice(env.allocator, ema.items);
                    const str_builtin = env.getBuiltinObject("String") orelse return error.UndefinedObject;
                    const method_fn = str_builtin.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                    const result = method_fn(ma.items, env);
                    if (env.throw_hit) return error.Thrown;
                    return switch (result) {
                        .value => |val| val,
                        .void => .void,
                    };
                }
                var stack_buf5: [16]ast.Value = undefined;
                stack_buf5[0] = value;
                const total5 = 1 + m.arguments.len;
                if (total5 <= 16) {
                    for (m.arguments, 0..) |arg, idx| {
                        stack_buf5[idx + 1] = try evaluate(arg, env);
                    }
                    const str_builtin = env.getBuiltinObject("String") orelse return error.UndefinedObject;
                    const method_fn = str_builtin.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                    const result5 = method_fn(stack_buf5[0..total5], env);
                    if (env.throw_hit) return error.Thrown;
                    return switch (result5) {
                        .value => |val| val,
                        .void => .void,
                    };
                }
                var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, total5);
                defer method_args.deinit(env.allocator);
                try method_args.append(env.allocator, value);
                for (m.arguments) |arg| {
                    const val = try evaluate(arg, env);
                    try method_args.append(env.allocator, val);
                }
                const str_builtin2 = env.getBuiltinObject("String") orelse return error.UndefinedObject;
                const method_fn2 = str_builtin2.getMethod(m.method) orelse {
    const _msg = std.fmt.allocPrint(env.allocator, "{s} is not a function", .{m.method}) catch {
        _ = throwError(env, "TypeError", .{ .string = "is not a function" });
        return error.Thrown;
    };
    defer env.allocator.free(_msg);
    _ = throwError(env, "TypeError", .{ .string = _msg });
    return error.Thrown;
};
                const result5 = method_fn2(method_args.items, env);
                if (env.throw_hit) return error.Thrown;
                return switch (result5) {
                    .value => |val| val,
                    .void => .void,
                };
            } else if (value == .closure) {
                if (isFunctionProtoMethod(m.method)) {
                    return try evaluateFunctionPrototypeMethod(m.method, value, m.arguments, env);
                }
                var closure_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, m.arguments.len);
                defer closure_args.deinit(env.allocator);
                for (m.arguments) |arg| try closure_args.append(env.allocator, try evaluate(arg, env));
                return try callFunctionValue(value, closure_args.items, env, ast.Value{ .void = {} });
            } else if (value == .function) {
                if (isFunctionProtoMethod(m.method)) {
                    return try evaluateFunctionPrototypeMethod(m.method, value, m.arguments, env);
                }
                const func_node: *ast.Node = @alignCast(@ptrCast(value.function));

                const has_spread = if (expanded_method_args) |ema| ema.items.len > 0 else false;
                _ = has_spread;

                if (expanded_method_args) |ema| {
                    return try invokeFunctionNode(func_node, ema.items, env, value);
                }
                var mc_stack: [16]ast.Value = undefined;
                const mc_total = m.arguments.len;
                if (mc_total <= 16) {
                    for (m.arguments, 0..) |arg, idx| {
                        mc_stack[idx] = try evaluate(arg, env);
                    }
                    return try invokeFunctionNode(func_node, mc_stack[0..mc_total], env, value);
                }
                {
                    var mc_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, mc_total);
                    defer mc_args.deinit(env.allocator);
                    for (m.arguments) |arg| {
                        try mc_args.append(env.allocator, try evaluate(arg, env));
                    }
                    return try invokeFunctionNode(func_node, mc_args.items, env, value);
                }
            } else {
                return error.InvalidMethodCall;
            }
        },
        .ImportStatement => |i| {
            const allocator = env.allocator;
            const io = env.io orelse return error.NoIo;

            var full_path: []const u8 = undefined;
            var needs_free = false;
            if (i.module_path.len > 0 and i.module_path[0] == '/') {
                full_path = i.module_path;
            } else if (env.module_dir) |dir| {
                full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, i.module_path });
                needs_free = true;
            } else {
                full_path = i.module_path;
            }
            defer if (needs_free) allocator.free(full_path);

            var root = env;
            while (root.outer) |outer| root = outer;

            var cached_exports: ?*const std.StringHashMap(ast.Value) = null;
            var cached_functions: ?*const std.StringHashMap(*ast.Node) = null;

            if (root.module_cache.get(full_path)) |cached| {
                cached_exports = &cached.exports;
                cached_functions = &cached.functions;
            }

            if (cached_exports == null) {
                const content = try env_mod.Io.Dir.cwd().readFileAlloc(io, full_path, allocator, env_mod.Io.Limit.limited(10 * 1024 * 1024));
                var resources_stored = false;
                errdefer if (!resources_stored) allocator.free(content);

                const LexerT = @import("lexer.zig").Lexer;
                const ParserT = @import("parser.zig").Parser;
                var lexer = LexerT.init(content);
                var parser = try ParserT.init(&lexer, allocator);
                errdefer if (!resources_stored) parser.deinit();
                const statements = try parser.parseProgram();

                try root.module_contents.append(root.allocator, content);
                try root.module_arenas.append(root.allocator, parser.arena);
                resources_stored = true;

                var module_dir: []const u8 = ".";
                if (std.mem.lastIndexOfScalar(u8, full_path, '/')) |idx| {
                    module_dir = full_path[0..idx];
                }

                var module_env = try Environment.initWithIo(allocator, null, io);
                defer module_env.deinit();
                module_env.module_dir = module_dir;

                for (statements) |stmt| {
                    _ = try evaluate(stmt, &module_env);
                }

                var cache_entry = env_mod.ModuleCacheEntry{
                    .exports = std.StringHashMap(ast.Value).init(allocator),
                    .functions = std.StringHashMap(*ast.Node).init(allocator),
                };
                {
                    var it = module_env.exports.iterator();
                    while (it.next()) |entry| {
                        try cache_entry.exports.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
                {
                    var it = module_env.functions.iterator();
                    while (it.next()) |entry| {
                        try cache_entry.functions.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
                const cache_key = try allocator.dupe(u8, full_path);
                errdefer allocator.free(cache_key);
                try root.module_cache.put(cache_key, cache_entry);

                cached_exports = &root.module_cache.get(cache_key).?.exports;
                cached_functions = &root.module_cache.get(cache_key).?.functions;
            }

            if (i.named_bindings) |bindings| {
                for (bindings) |binding| {
                    const export_name = binding.name;
                    const local_name = binding.alias orelse binding.name;
                    const val = cached_exports.?.get(export_name) orelse return error.ExportNotFound;
                    try env.setVar(local_name, val);
                    if (cached_functions.?.get(export_name)) |func_node| {
                        try env.setFunction(local_name, func_node);
                    }
                }
            }

            if (i.namespace) |_| {
                var it = cached_exports.?.iterator();
                while (it.next()) |entry| {
                    if (std.mem.eql(u8, entry.key_ptr.*, "default")) continue;
                    try env.setVar(entry.key_ptr.*, entry.value_ptr.*);
                    if (cached_functions.?.get(entry.key_ptr.*)) |func_node| {
                        try env.setFunction(entry.key_ptr.*, func_node);
                    }
                }
            }

            if (i.default_binding) |db| {
                const val = cached_exports.?.get("default") orelse return error.ExportNotFound;
                try env.setVar(db, val);
                if (cached_functions.?.get("default")) |func_node| {
                    try env.setFunction(db, func_node);
                }
            }

            return .{ .float = 0.0 };
        },
        .ExportStatement => |e| {
            const result = try evaluate(e.declaration, env);
            const decl_name: ?[]const u8 = switch (e.declaration.*) {
                .ConstantDeclaration => |c| c.name,
                .VariableDeclaration => |v| v.name,
                .LetDeclaration => |v| v.name,
                .FunctionDeclaration => |f| f.name,
                else => null,
            };

            if (e.is_default) {
                if (decl_name) |n| {
                    if (env.get(n)) |v| {
                        try env.exports.put("default", v);
                    } else if (env.getFunction(n)) |_| {
                        try env.exports.put("default", result);
                    } else {
                        try env.exports.put("default", result);
                    }
                } else {
                    try env.exports.put("default", result);
                }
            }

            if (!e.is_default) {
                if (decl_name) |n| {
                    if (env.get(n)) |v| {
                        try env.exports.put(n, v);
                    } else if (env.getFunction(n)) |_| {
                        try env.exports.put(n, result);
                    } else {
                        return error.ExportNotFound;
                    }
                }
            }

            return result;
        },
        .SpreadExpression => {
            // SpreadExpression should only appear inside array/object literals and function call arguments.
            // It should never be evaluated as a standalone expression.
            return error.UnexpectedSpreadExpression;
        },
        .Elision => {
            // Elision should only appear inside array literals.
            return error.UnexpectedElision;
        },
.CommaExpression => |c| {
             var result: ast.Value = .{ .float = 0.0 };
             for (c.expressions) |e| {
                 result = try evaluate(e, env);
                 // Debug: log intermediate results
                 // std.debug.print("comma expr: {}\n", .{result});
             }
             return result;
         },
    }
}

// ============================================================================
// Tests
// ============================================================================

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn callRegExpMethod(recv: ast.Value, method: []const u8, arg_nodes: []*ast.Node, env: *Environment) anyerror!ast.Value {
    const builtin_obj = env.getBuiltinObject("RegExp") orelse return .{ .void = {} };
    const method_fn = builtin_obj.getMethod(method) orelse return .{ .void = {} };
    var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 1 + arg_nodes.len);
    defer args.deinit(env.allocator);
    try args.append(env.allocator, recv);
    for (arg_nodes) |arg| {
        try args.append(env.allocator, try evaluate(arg, env));
    }
    const result = method_fn(args.items, env);
    return switch (result) {
        .value => |val| val,
        .void => .{ .void = {} },
    };
}

fn parseAndEvaluate(source: []const u8, env_: *Environment) !ast.Value {
    var lexer = Lexer.init(source);
    var parser = try Parser.init(&lexer, env_.allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();
    return try evaluate(node, env_);
}

fn parseAndEvaluateProgram(source: []const u8, env_: *Environment) !ast.Value {
    var lexer = Lexer.init(source);
    var parser = try Parser.init(&lexer, env_.allocator);
    defer parser.deinit();
    const statements = try parser.parseProgram();
    var result: ast.Value = .{ .float = 0.0 };
    for (statements) |stmt| {
        result = try evaluate(stmt, env_);
    }
    return result;
}

/// Evaluate a whole program and drain Promise reactions before releasing the
/// parser arena, because queued callbacks still reference its AST nodes.
fn parseEvaluateAndDrain(source: []const u8, env_: *Environment) !void {
    var lexer = Lexer.init(source);
    var parser = try Parser.init(&lexer, env_.allocator);
    defer parser.deinit();
    const statements = try parser.parseProgram();
    for (statements) |stmt| {
        _ = try evaluate(stmt, env_);
    }
    drainPromiseJobs(env_);
}

pub fn resolveArgumentIn(
    idx: usize,
    args: []ast.Value,
    param_defaults: []?*ast.Node,
    func_env: *Environment,
) anyerror!ast.Value {
    if (idx < args.len and args[idx] != .void) return args[idx];
    if (idx < param_defaults.len) {
        if (param_defaults[idx]) |expr| return try evaluate(expr, func_env);
    }
    return .{ .void = {} };
}

fn getSuperProperty(env: *Environment, key: []const u8) anyerror!ast.Value {
    const parent = env.get("@@super") orelse return .{ .void = {} };
    const this_val: ast.Value = env.get("this") orelse .{ .void = {} };
    var target = classPrototypeOf(parent) orelse return .{ .void = {} };
    if (this_val == .js_object and this_val.js_object.properties.get("@@class") != null) {
        target = parent.js_object;
    }
    var cur: ?*ast.ObjectValue = target;
    while (cur) |o| {
        if (o.properties.get(key)) |v| {
            if (accessorPart(v, "get")) |getter| {
                return try callFunctionValue(getter, &[_]ast.Value{}, env, this_val);
            }
            if (isAccessorValue(v)) return .{ .void = {} };
            return v;
        }
        cur = o.prototype;
    }
    return .{ .void = {} };
}

fn findPropertyInChain(obj: *ast.ObjectValue, key: []const u8) ?ast.Value {
    var cur: ?*ast.ObjectValue = obj;
    while (cur) |o| {
        if (o.properties.get(key)) |v| return v;
        cur = o.prototype;
    }
    return null;
}

fn classPrototypeOf(class_val: ast.Value) ?*ast.ObjectValue {
    if (class_val != .js_object) return null;
    const proto = class_val.js_object.properties.get("prototype") orelse return null;
    if (proto != .js_object) return null;
    return proto.js_object;
}

fn classConstructorOf(class_val: ast.Value) ?ast.Value {
    if (class_val != .js_object) return null;
    return class_val.js_object.properties.get("@@ctor");
}

fn classNodeOf(class_val: ast.Value) ?*ast.Node {
    if (class_val != .js_object) return null;
    const node_val = class_val.js_object.properties.get("@@class_node") orelse return null;
    if (node_val != .function) return null;
    return @ptrCast(@alignCast(node_val.function));
}

fn classScopeOf(class_val: ast.Value) ?*Environment {
    if (class_val != .js_object) return null;
    const scope_val = class_val.js_object.properties.get("@@scope") orelse return null;
    if (scope_val != .function) return null;
    return @ptrCast(@alignCast(scope_val.function));
}

fn initClassFields(env: *Environment, class_val: ast.Value, instance: ast.Value) anyerror!void {
    const node = classNodeOf(class_val) orelse return;
    if (node.* != .ClassDeclaration and node.* != .ClassExpression) return;
    const fields = switch (node.*) {
        .ClassDeclaration => |c| c.fields,
        .ClassExpression => |c| c.fields,
        else => unreachable,
    };
    if (fields.len == 0) return;
    const scope = classScopeOf(class_val) orelse env;
    var field_env = try Environment.initBlock(env.allocator, scope);
    defer field_env.deinit();
    try field_env.set("this", instance);
    for (fields) |field| {
        if (field.is_static) continue;
        const value: ast.Value = if (field.value) |expr| try evaluate(expr, &field_env) else .{ .void = {} };
        try instance.js_object.properties.put(field.name, value);
    }
}

fn invokeClassConstructor(ctor: ast.Value, args: []ast.Value, env: *Environment, instance: ast.Value) anyerror!ast.Value {
    if (ctor != .closure) return callFunctionValue(ctor, args, env, instance);
    const scope: *Environment = @alignCast(@ptrCast(ctor.closure.env));
    const node: *ast.Node = @alignCast(@ptrCast(ctor.closure.func_node));
    if (node.* != .FunctionDeclaration) return callFunctionValue(ctor, args, env, instance);
    const func = node.FunctionDeclaration;
    const func_env = try Environment.initHeap(env.allocator, scope);
    defer if (!func_env.captured) {
        func_env.deinit();
        env.allocator.destroy(func_env);
    };
    try func_env.set("this", instance);
    for (func.parameters, 0..) |param, idx| {
        try func_env.set(param, try resolveArgumentIn(idx, args, func.param_defaults, func_env));
    }
    try bindRestArguments(func_env, func.parameters, func.rest_param, args);
    if (func.body.* == .BlockStatement) predeclareLexicals(func_env, func.body.BlockStatement.statements);
    const result = evaluate(func.body, func_env) catch |err| {
        if (func_env.throw_hit) {
            env.throw_hit = true;
            env.throw_value = func_env.throw_value;
        }
        return err;
    };
    if (!func_env.return_hit) return instance;
    return switch (result) {
        .js_object, .array, .function, .closure, .generator, .regexp, .iterator, .array_iterator, .symbol, .object => result,
        else => instance,
    };
}

fn constructClass(env: *Environment, class_val: ast.Value, args: []ast.Value) anyerror!ast.Value {
    const proto = classPrototypeOf(class_val) orelse return error.NotAConstructor;
    const instance_obj = try ast.ObjectValue.init(env.allocator);
    instance_obj.prototype = proto;
    try env.objects.append(env.allocator, instance_obj);
    const instance = ast.Value{ .js_object = instance_obj };

    const parent = class_val.js_object.properties.get("@@super");
    if (parent) |parent_val| {
        if (parent_val == .js_object) try initClassFields(env, parent_val, instance);
    }
    try initClassFields(env, class_val, instance);

    if (classConstructorOf(class_val)) |ctor| {
        return try invokeClassConstructor(ctor, args, env, instance);
    }

    if (parent) |parent_val| {
        if (classConstructorOf(parent_val)) |parent_ctor| {
            _ = try callFunctionValue(parent_ctor, args, env, instance);
        }
    }
    return instance;
}

fn putClassAccessor(env: *Environment, target: *ast.ObjectValue, name: []const u8, kind: ast.ClassMethodKind, method: ast.Value) !void {
    var accessor: *ast.ObjectValue = undefined;
    if (target.properties.get(name)) |existing| {
        if (isAccessorValue(existing)) {
            accessor = existing.js_object;
        } else {
            accessor = try ast.ObjectValue.init(env.allocator);
            try env.objects.append(env.allocator, accessor);
            try accessor.properties.put("@@native", .{ .string = "Accessor" });
            try target.properties.put(name, .{ .js_object = accessor });
        }
    } else {
        accessor = try ast.ObjectValue.init(env.allocator);
        try env.objects.append(env.allocator, accessor);
        try accessor.properties.put("@@native", .{ .string = "Accessor" });
        try target.properties.put(name, .{ .js_object = accessor });
    }
    const key = if (kind == .get) "get" else "set";
    try accessor.properties.put(key, method);
}

fn createClassValue(
    env: *Environment,
    node: *ast.Node,
    name: []const u8,
    superclass: ?*ast.Node,
    methods: []ast.ClassMethod,
    fields: []ast.ClassField,
) anyerror!ast.Value {
    var parent_val: ?ast.Value = null;
    if (superclass) |sc| {
        const val = try evaluate(sc, env);
        if (classPrototypeOf(val) == null) {
            _ = throwError(env, "TypeError", .{ .string = "Class extends value is not a constructor" });
            return error.Thrown;
        }
        parent_val = val;
    }

    const parent_proto = if (parent_val) |pv| classPrototypeOf(pv) else null;
    const proto = try ast.ObjectValue.init(env.allocator);
    proto.prototype = parent_proto;
    try env.objects.append(env.allocator, proto);

    const class_obj = try ast.ObjectValue.init(env.allocator);
    class_obj.prototype = if (parent_val) |pv| pv.js_object else env.object_prototype;
    try env.objects.append(env.allocator, class_obj);
    const class_val = ast.Value{ .js_object = class_obj };
    try class_obj.properties.put("prototype", .{ .js_object = proto });
    try class_obj.properties.put("name", .{ .string = name });
    try class_obj.properties.put("@@class", .{ .boolean = true });
    try class_obj.properties.put("@@class_node", .{ .function = @ptrCast(node) });
    if (parent_val) |pv| try class_obj.properties.put("@@super", pv);

    if (methods.len > 0 or fields.len > 0) {
        const scope = try Environment.initClosureHeap(env.allocator, try env.captureEnv());
        try scope.set("@@class", class_val);
        try scope.set("@@class_node", .{ .function = @ptrCast(node) });
        if (parent_val) |pv| try scope.set("@@super", pv);
        try class_obj.properties.put("@@scope", .{ .function = @ptrCast(scope) });
        if (name.len > 0) try scope.set(name, class_val);

        var ctor_val: ?ast.Value = null;
        for (methods) |method| {
            const closure = ast.Value{ .closure = try ast.ClosureValue.init(env.allocator, @ptrCast(method.function), @ptrCast(scope)) };
            if (method.kind == .constructor and !method.is_static) {
                ctor_val = closure;
            } else if (method.kind == .get or method.kind == .set) {
                const target = if (method.is_static) class_obj else proto;
                try putClassAccessor(env, target, method.name, method.kind, closure);
            } else {
                const target = if (method.is_static) class_obj else proto;
                try target.properties.put(method.name, closure);
            }
        }
        if (ctor_val) |cv| try class_obj.properties.put("@@ctor", cv);

        for (fields) |field| {
            if (!field.is_static) continue;
            const value: ast.Value = if (field.value) |expr| try evaluate(expr, scope) else .{ .void = {} };
            try class_obj.properties.put(field.name, value);
        }
    }

    return class_val;
}

fn invokeSuperConstructor(env: *Environment, args: []ast.Value) anyerror!ast.Value {
    const parent = env.get("@@super") orelse return error.NotAConstructor;
    const parent_ctor = classConstructorOf(parent) orelse return error.NotAConstructor;
    const this_val = env.get("this") orelse return error.NotAConstructor;
    try initClassFields(env, parent, this_val);
    return try invokeClassConstructor(parent_ctor, args, env, this_val);
}

fn callSuperMethod(env: *Environment, method: []const u8, args: []ast.Value) anyerror!ast.Value {
    const parent = env.get("@@super") orelse return error.NotAFunction;
    const this_val: ast.Value = env.get("this") orelse .{ .void = {} };
    var cur = if (this_val == .js_object and this_val.js_object.properties.get("@@class") != null)
        parent.js_object
    else
        classPrototypeOf(parent) orelse return error.NotAFunction;
    var found: ?ast.Value = null;
    while (true) {
        if (cur.properties.get(method)) |v| {
            found = v;
            break;
        }
        cur = cur.prototype orelse break;
    }
    const method_val = found orelse return error.NotAFunction;
    if (accessorPart(method_val, "get")) |getter| {
        return try callFunctionValue(getter, &[_]ast.Value{}, env, this_val);
    }
    return try callFunctionValue(method_val, args, env, this_val);
}
fn bindRestArguments(dest: *Environment, parameters: []const []const u8, rest_param: ?[]const u8, args: []ast.Value) !void {
    const name = rest_param orelse return;
    const restrict = try ast.ArrayObject.init(dest.allocator);
    var idx = parameters.len;
    while (idx < args.len) : (idx += 1) {
        try restrict.elements.append(dest.allocator, args[idx]);
    }
    try dest.arrays.append(dest.allocator, restrict);
    try dest.set(name, .{ .array = restrict });
}
fn isCallableValue(value: ast.Value) bool {
    return switch (value) {
        .function, .closure, .generator => true,
        .js_object => |obj| obj.properties.get("@@callable") != null,
        else => false,
    };
}

fn constructPromise(env: *Environment, args: []ast.Value) anyerror!ast.Value {
    const pending = promiseMod.createPending(env);
    if (pending != .js_object) return pending;

    if (args.len == 0 or !isCallableValue(args[0])) {
        _ = throwError(env, "TypeError", .{ .string = "Promise resolver is not a function" });
        const reason = if (env.throw_hit) env.throw_value else ast.Value{ .string = "TypeError" };
        env.throw_hit = false;
        env.throw_value = .{ .void = {} };
        promiseMod.rejectPromise(pending.js_object, reason);
        return pending;
    }

    const resolve_fn = promiseMod.makeResolver(env, pending, false);
    const reject_fn = promiseMod.makeResolver(env, pending, true);
    var call_args = [2]ast.Value{ resolve_fn, reject_fn };
    _ = callFunctionValue(args[0], call_args[0..], env, .{ .void = {} }) catch {
        const reason = if (env.throw_hit) env.throw_value else ast.Value{ .string = "Error" };
        env.throw_hit = false;
        env.throw_value = .{ .void = {} };
        promiseMod.rejectPromise(pending.js_object, reason);
        return pending;
    };
    if (env.throw_hit) {
        const reason = env.throw_value;
        env.throw_hit = false;
        env.throw_value = .{ .void = {} };
        promiseMod.rejectPromise(pending.js_object, reason);
    }
    return pending;
}

fn awaitValue(env: *Environment, value: ast.Value) anyerror!ast.Value {
    if (!promiseMod.isPromise(value)) return value;
    var state = promiseMod.promiseState(value);
    if (std.mem.eql(u8, state, "pending")) {
        drainPromiseJobs(env);
        state = promiseMod.promiseState(value);
    }
    if (std.mem.eql(u8, state, "fulfilled")) return promiseMod.promiseValue(value);
    if (std.mem.eql(u8, state, "rejected")) {
        env.throw_hit = true;
        env.throw_value = promiseMod.promiseValue(value);
        return error.Thrown;
    }
    return .{ .void = {} };
}

fn invokeAsyncFunctionNode(func_node: *ast.Node, args: []ast.Value, env: *Environment, this_val: ?ast.Value) anyerror!ast.Value {
    const pending = promiseMod.createPending(env);
    if (pending != .js_object) return pending;

    const func_env = try Environment.initHeap(env.allocator, env);
    defer if (!func_env.captured) {
        func_env.deinit();
        env.allocator.destroy(func_env);
    };

    var body: *ast.Node = undefined;
    if (func_node.* == .FunctionDeclaration) {
        const func = func_node.FunctionDeclaration;
        if (this_val) |tv| {
            const bound_this: ast.Value = switch (tv) {
                .null, .void => if (env.globalObject()) |g| ast.Value{ .js_object = g } else tv,
                else => tv,
            };
            try func_env.set("this", bound_this);
        }
        for (func.parameters, 0..) |param, idx| {
            try func_env.set(param, try resolveArgumentIn(idx, args, func.param_defaults, func_env));
        }
        try bindRestArguments(func_env, func.parameters, func.rest_param, args);
        body = func.body;
    } else if (func_node.* == .ArrowFunction) {
        const func = func_node.ArrowFunction;
        const lexical_this = env.get("this") orelse ast.Value{ .void = {} };
        try func_env.set("this", lexical_this);
        for (func.parameters, 0..) |param, idx| {
            try func_env.set(param, try resolveArgumentIn(idx, args, func.param_defaults, func_env));
        }
        try bindRestArguments(func_env, func.parameters, func.rest_param, args);
        body = func.body;
    } else {
        return error.NotAFunction;
    }

    if (body.* == .BlockStatement) predeclareLexicals(func_env, body.BlockStatement.statements);
    const expression_body = body.* != .BlockStatement;
    const result = evaluate(body, func_env) catch {
        const reason = if (func_env.throw_hit) func_env.throw_value else ast.Value{ .string = "Error" };
        promiseMod.rejectPromise(pending.js_object, reason);
        return pending;
    };
    if (func_env.throw_hit) {
        const reason = func_env.throw_value;
        func_env.throw_hit = false;
        func_env.throw_value = .{ .void = {} };
        promiseMod.rejectPromise(pending.js_object, reason);
        return pending;
    }
    const settled = if (!expression_body and !func_env.return_hit) ast.Value{ .void = {} } else result;
    promiseMod.resolvePromise(env, pending.js_object, settled);
    return pending;
}

fn settleReactionChild(env: *Environment, child: ast.Value, state: []const u8, value: ast.Value) void {
    if (child != .js_object) return;
    if (std.mem.eql(u8, state, "fulfilled")) {
        promiseMod.resolvePromise(env, child.js_object, value);
    } else {
        promiseMod.rejectPromise(child.js_object, value);
    }
}

fn processAggregateReaction(env: *Environment, reaction: *ast.ObjectValue) bool {
    const parent = reaction.properties.get("parent") orelse return true;
    const result = reaction.properties.get("@@result") orelse return true;
    if (!promiseMod.isPromise(parent) or !promiseMod.isPromise(result)) return true;
    if (!promiseMod.isPending(result)) return true;

    const state = promiseMod.promiseState(parent);
    if (std.mem.eql(u8, state, "pending")) return false;
    const parent_value = promiseMod.promiseValue(parent);
    const kind_val = reaction.properties.get("@@kind") orelse return true;
    const kind = if (kind_val == .string) kind_val.string else "";
    const index_val = reaction.properties.get("@@index") orelse return true;
    const index: usize = if (index_val == .integer and index_val.integer >= 0) @intCast(index_val.integer) else 0;
    const slots_val = reaction.properties.get("@@values") orelse ast.Value{ .void = {} };
    const remaining_val = result.js_object.properties.get("@@remaining") orelse ast.Value{ .integer = 0 };
    const rejected_val = result.js_object.properties.get("@@rejected") orelse ast.Value{ .integer = 0 };
    var remaining: usize = if (remaining_val == .integer and remaining_val.integer > 0) @intCast(remaining_val.integer) else 0;
    var rejected: usize = if (rejected_val == .integer and rejected_val.integer > 0) @intCast(rejected_val.integer) else 0;

    if (std.mem.eql(u8, kind, "all")) {
        if (std.mem.eql(u8, state, "rejected")) {
            settleReactionChild(env, result, "rejected", parent_value);
            return true;
        }
        if (slots_val == .array) slots_val.array.set(index, parent_value) catch {};
        if (remaining > 0) remaining -= 1;
        if (remaining == 0) settleReactionChild(env, result, "fulfilled", slots_val);
        result.js_object.properties.put("@@remaining", .{ .integer = @intCast(remaining) }) catch {};
        return true;
    }

    if (std.mem.eql(u8, kind, "allSettled")) {
        const record = ast.ObjectValue.init(env.allocator) catch return true;
        env.objects.append(env.allocator, record) catch {};
        if (std.mem.eql(u8, state, "rejected")) {
            record.properties.put("status", .{ .string = "rejected" }) catch {};
            record.properties.put("reason", parent_value) catch {};
        } else {
            record.properties.put("status", .{ .string = "fulfilled" }) catch {};
            record.properties.put("value", parent_value) catch {};
        }
        if (slots_val == .array) slots_val.array.set(index, .{ .js_object = record }) catch {};
        if (remaining > 0) remaining -= 1;
        if (remaining == 0) settleReactionChild(env, result, "fulfilled", slots_val);
        result.js_object.properties.put("@@remaining", .{ .integer = @intCast(remaining) }) catch {};
        return true;
    }

    if (std.mem.eql(u8, kind, "race")) {
        settleReactionChild(env, result, state, parent_value);
        return true;
    }

    if (std.mem.eql(u8, kind, "any")) {
        if (std.mem.eql(u8, state, "fulfilled")) {
            settleReactionChild(env, result, "fulfilled", parent_value);
        } else {
            rejected += 1;
            result.js_object.properties.put("@@rejected", .{ .integer = @intCast(rejected) }) catch {};
            if (remaining > 0 and rejected >= remaining) {
                settleReactionChild(env, result, "rejected", .{ .string = "AggregateError: All promises were rejected" });
            }
        }
        return true;
    }

    return true;
}
fn processPromiseReaction(env: *Environment, job: ast.Value) bool {
    if (job != .js_object) return true;
    const reaction = job.js_object;
    if (reaction.properties.get("@@aggregate")) |agg_flag| {
        if (agg_flag == .boolean and agg_flag.boolean) return processAggregateReaction(env, reaction);
    }
    const parent = reaction.properties.get("parent") orelse return true;
    const child = reaction.properties.get("child") orelse return true;
    if (!promiseMod.isPromise(parent) or !promiseMod.isPromise(child)) return true;
    if (!promiseMod.isPending(child)) return true;

    const state = promiseMod.promiseState(parent);
    if (std.mem.eql(u8, state, "pending")) return false;
    const parent_value = promiseMod.promiseValue(parent);

    if (reaction.properties.get("onFinally")) |on_finally| {
        if (isCallableValue(on_finally)) {
            env.throw_hit = false;
            env.throw_value = .{ .void = {} };
            _ = callFunctionValue(on_finally, &[_]ast.Value{}, env, .{ .void = {} }) catch {
                const reason = if (env.throw_hit) env.throw_value else ast.Value{ .string = "Error" };
                env.throw_hit = false;
                env.throw_value = .{ .void = {} };
                promiseMod.rejectPromise(child.js_object, reason);
                return true;
            };
            if (env.throw_hit) {
                const reason = env.throw_value;
                env.throw_hit = false;
                env.throw_value = .{ .void = {} };
                promiseMod.rejectPromise(child.js_object, reason);
                return true;
            }
        }
        settleReactionChild(env, child, state, parent_value);
        return true;
    }

    const handler = if (std.mem.eql(u8, state, "fulfilled"))
        reaction.properties.get("onFulfilled")
    else
        reaction.properties.get("onRejected");

    if (handler == null or !isCallableValue(handler.?)) {
        settleReactionChild(env, child, state, parent_value);
        return true;
    }

    env.throw_hit = false;
    env.throw_value = .{ .void = {} };
    var call_args = [1]ast.Value{parent_value};
    const result = callFunctionValue(handler.?, call_args[0..], env, .{ .void = {} }) catch {
        const reason = if (env.throw_hit) env.throw_value else ast.Value{ .string = "Error" };
        env.throw_hit = false;
        env.throw_value = .{ .void = {} };
        promiseMod.rejectPromise(child.js_object, reason);
        return true;
    };
    if (env.throw_hit) {
        const reason = env.throw_value;
        env.throw_hit = false;
        env.throw_value = .{ .void = {} };
        promiseMod.rejectPromise(child.js_object, reason);
        return true;
    }
    promiseMod.resolvePromise(env, child.js_object, result);
    return true;
}

pub fn drainPromiseJobs(env: *Environment) void {
    const root = env.root();
    var progress = true;
    while (progress) {
        progress = false;
        var i: usize = 0;
        while (i < root.promise_jobs.items.len) {
            if (processPromiseReaction(env, root.promise_jobs.items[i])) {
                _ = root.promise_jobs.orderedRemove(i);
                progress = true;
            } else {
                i += 1;
            }
        }
    }
}
fn invokeFunctionNode(func_node: *ast.Node, args: []ast.Value, env: *Environment, this_val: ?ast.Value) anyerror!ast.Value {
        if (func_node.* == .GeneratorDeclaration) {
            const gen_decl = func_node.GeneratorDeclaration;
            const gen_obj = try GeneratorObject.init(env.allocator, @ptrCast(func_node), gen_decl.parameters);
            errdefer gen_obj.deinit();
            gen_obj.is_async = gen_decl.is_async;
            var gen_env = try Environment.init(env.allocator, env);
            errdefer gen_env.deinit();
            if (this_val) |tv| {
                try gen_env.set("this", tv);
            }
            for (gen_decl.parameters, 0..) |param, idx| {
                try gen_env.set(param, try resolveArgumentIn(idx, args, gen_decl.param_defaults, &gen_env));
            }
            try bindRestArguments(&gen_env, gen_decl.parameters, gen_decl.rest_param, args);
        gen_obj.gen_env = @ptrCast(try env.allocator.create(Environment));
        const stored_env: *Environment = @alignCast(@ptrCast(gen_obj.gen_env.?));
        stored_env.* = gen_env;
        try env.generators.append(env.allocator, gen_obj);
        return .{ .generator = gen_obj };
    }
        const traced = func_node.* == .FunctionDeclaration or func_node.* == .ArrowFunction;
        if (traced) {
            const frame_name: []const u8 = switch (func_node.*) {
                .FunctionDeclaration => |f| if (f.name.len > 0) f.name else "<anonymous>",
                else => "<anonymous>",
            };
            env.pushTraceFrame(frame_name, 0);
        }
        defer if (traced) env.popTraceFrame();
        if (func_node.* == .FunctionDeclaration and func_node.FunctionDeclaration.is_async) {
            return try invokeAsyncFunctionNode(func_node, args, env, this_val);
        }
        if (func_node.* == .ArrowFunction and func_node.ArrowFunction.is_async) {
            return try invokeAsyncFunctionNode(func_node, args, env, this_val);
        }
        if (func_node.* == .FunctionDeclaration) {
            const func = func_node.FunctionDeclaration;
            // Heap-owned so closures created in the body can adopt it; freed
            // right away unless one of them actually captured it.
            const func_env = try Environment.initHeap(env.allocator, env);
            defer if (!func_env.captured) {
                func_env.deinit();
                env.allocator.destroy(func_env);
            };
            if (this_val) |tv| {
                // Sloppy-mode `this` coercion: null/undefined become the global object.
                const bound_this: ast.Value = switch (tv) {
                    .null, .void => if (env.globalObject()) |g| ast.Value{ .js_object = g } else tv,
                    else => tv,
                };
                try func_env.set("this", bound_this);
            }
            for (func.parameters, 0..) |param, idx| {
                try func_env.set(param, try resolveArgumentIn(idx, args, func.param_defaults, func_env));
            }
            try bindRestArguments(func_env, func.parameters, func.rest_param, args);
            if (func.body.* == .BlockStatement) predeclareLexicals(func_env, func.body.BlockStatement.statements);
            const result = evaluate(func.body, func_env) catch |err| {
                if (func_env.throw_hit) {
                    env.throw_hit = true;
                    env.throw_value = func_env.throw_value;
                }
                return err;
            };
            if (func_env.throw_hit) {
                env.throw_hit = true;
                env.throw_value = func_env.throw_value;
                return error.Thrown;
            }
            return result;
        }
        if (func_node.* == .ArrowFunction) {
            const func = func_node.ArrowFunction;
            const func_env = try Environment.initHeap(env.allocator, env);
            defer if (!func_env.captured) {
                func_env.deinit();
                env.allocator.destroy(func_env);
            };
            // Inherit this from outer lexical environment
            const lexical_this = env.get("this") orelse (ast.Value){ .void = {} };
            try func_env.set("this", lexical_this);
            for (func.parameters, 0..) |param, idx| {
                try func_env.set(param, try resolveArgumentIn(idx, args, func.param_defaults, func_env));
            }
            try bindRestArguments(func_env, func.parameters, func.rest_param, args);
            if (func.body.* == .BlockStatement) predeclareLexicals(func_env, func.body.BlockStatement.statements);
            const result = evaluate(func.body, func_env) catch |err| {
                if (func_env.throw_hit) {
                    env.throw_hit = true;
                    env.throw_value = func_env.throw_value;
                }
                return err;
            };
            if (func_env.throw_hit) {
                env.throw_hit = true;
                env.throw_value = func_env.throw_value;
                return error.Thrown;
            }
            return result;
        }
    return error.NotAFunction;
}

fn isAccessorValue(val: ast.Value) bool {
    if (val != .js_object) return false;
    const tag = val.js_object.properties.get("@@native") orelse return false;
    return tag == .string and std.mem.eql(u8, tag.string, "Accessor");
}

fn accessorPart(val: ast.Value, part: []const u8) ?ast.Value {
    if (!isAccessorValue(val)) return null;
    return val.js_object.properties.get(part);
}

fn findAccessorValue(obj: *ast.ObjectValue, key: []const u8) ?ast.Value {
    var cur: ?*ast.ObjectValue = obj;
    while (cur) |o| {
        if (o.properties.get(key)) |v| {
            return if (isAccessorValue(v)) v else null;
        }
        cur = o.prototype;
    }
    return null;
}

fn setAccessorProperty(env: *Environment, obj: *ast.ObjectValue, key: []const u8, val: ast.Value) !bool {
    const acc = findAccessorValue(obj, key) orelse return false;
    if (acc.js_object.properties.get("set")) |setter| {
        var setter_args = [_]ast.Value{val};
        _ = try callFunctionValue(setter, &setter_args, env, .{ .js_object = obj });
    }
    return true;
}

fn isFunctionProtoMethod(method: []const u8) bool {
    return std.mem.eql(u8, method, "call") or std.mem.eql(u8, method, "apply") or std.mem.eql(u8, method, "bind");
}

fn functionProtoReceiver(env: *Environment, node: *ast.Node) ?ast.Value {
    if (node.* != .Identifier) return null;
    const name = node.Identifier.name;
    if (env.get(name)) |v| return v;
    if (env.getFunction(name)) |fn_node| return .{ .function = @ptrCast(@alignCast(fn_node)) };
    return null;
}

/// Invokes a bound-function wrapper: concatenates the wrapper's bound
/// arguments with the call arguments and unwraps nested bound wrappers until
/// a real function is reached.
pub fn invokeBoundFunction(obj: *ast.ObjectValue, extra_args: []const ast.Value, env: *Environment) anyerror!ast.Value {
    const info = functionMod.extractBoundFunction(obj) orelse return error.NotAFunction;
    var merged = try std.ArrayList(ast.Value).initCapacity(env.allocator, info.bound_args.len + extra_args.len);
    defer merged.deinit(env.allocator);
    try merged.appendSlice(env.allocator, info.bound_args);
    try merged.appendSlice(env.allocator, extra_args);
    if (info.target == .js_object and functionMod.isBoundFunction(info.target.js_object)) {
        return try invokeBoundFunction(info.target.js_object, merged.items, env);
    }
    return try callFunctionValue(info.target, merged.items, env, info.bound_this);
}

fn evaluateFunctionPrototypeMethod(method: []const u8, receiver: ast.Value, arg_nodes: []*ast.Node, env: *Environment) anyerror!ast.Value {
    var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, arg_nodes.len);
    defer args.deinit(env.allocator);
    for (arg_nodes) |n| try args.append(env.allocator, try evaluate(n, env));

    const this_arg: ast.Value = if (args.items.len > 0) args.items[0] else .{ .void = {} };
    if (std.mem.eql(u8, method, "bind")) {
        const bound_args: []const ast.Value = if (args.items.len > 1) args.items[1..] else &[_]ast.Value{};
        return .{ .js_object = functionMod.makeBoundFunction(env, receiver, this_arg, bound_args) };
    }

    var call_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, if (args.items.len > 1) args.items.len - 1 else 0);
    defer call_args.deinit(env.allocator);
    if (std.mem.eql(u8, method, "call")) {
        if (args.items.len > 1) try call_args.appendSlice(env.allocator, args.items[1..]);
    } else if (args.items.len > 1 and args.items[1] == .array) {
        try call_args.appendSlice(env.allocator, args.items[1].array.elements.items);
    }

    if (receiver == .js_object and functionMod.isBoundFunction(receiver.js_object)) {
        return try invokeBoundFunction(receiver.js_object, call_args.items, env);
    }
    return try callFunctionValue(receiver, call_args.items, env, this_arg);
}

fn ocIsNullish(v: ast.Value) bool {
    return v == .void or v == .null;
}

fn ocKeyString(value: ast.Value, env: *Environment) anyerror![]const u8 {
    return switch (value) {
        .string => |s| s,
        .integer => |i| blk: {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
            const owned = try env.allocator.dupe(u8, s);
            env.owned_strings.append(env.allocator, owned) catch {};
            break :blk owned;
        },
        .float => |f| blk: {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.OutOfMemory;
            const owned = try env.allocator.dupe(u8, s);
            env.owned_strings.append(env.allocator, owned) catch {};
            break :blk owned;
        },
        .symbol => |sym| blk: {
            const prop_name = try ast.symbolPropertyName(env.allocator, sym.description);
            env.owned_strings.append(env.allocator, prop_name) catch {};
            break :blk prop_name;
        },
        else => return error.InvalidIndex,
    };
}

fn ocMember(value: ast.Value, property: []const u8, env: *Environment) anyerror!ast.Value {
    if (value == .array) {
        if (std.mem.eql(u8, property, "length")) {
            return .{ .integer = @intCast(value.array.elements.items.len) };
        }
        const builtin_obj = env.getBuiltinObject("Array") orelse return error.UndefinedObject;
        if (builtin_obj.getMethod(property)) |_| {
            return .{ .object = @ptrCast(builtin_obj) };
        }
        return .{ .void = {} };
    }
    if (value == .iterator) return .{ .void = {} };
    if (value == .regexp) return regexpMod.getProperty(value.regexp, property);
    if (value == .js_object) {
        var cur: ?*ast.ObjectValue = value.js_object;
        while (cur) |o| {
            if (o.properties.get(property)) |v| {
                if (accessorPart(v, "get")) |getter| {
                    return try callFunctionValue(getter, &[_]ast.Value{}, env, .{ .js_object = value.js_object });
                }
                if (isAccessorValue(v)) return .{ .void = {} };
                return v;
            }
            cur = o.prototype;
        }
        return .{ .void = {} };
    }
    if (value == .object) {
        const bObjPtr: *const builtinsTypes.BuiltinObjectImpl = @ptrCast(@alignCast(value.object));
        if (bObjPtr.getProperty(property)) |prop_val| return prop_val;
        return .{ .void = {} };
    }
    return error.InvalidMemberAccess;
}

fn ocIndex(value: ast.Value, index_val: ast.Value, env: *Environment) anyerror!ast.Value {
    if (value == .js_object) {
        const key = try ocKeyString(index_val, env);
        var cur: ?*ast.ObjectValue = value.js_object;
        while (cur) |o| {
            if (o.properties.get(key)) |v| {
                if (accessorPart(v, "get")) |getter| {
                    return try callFunctionValue(getter, &[_]ast.Value{}, env, .{ .js_object = value.js_object });
                }
                if (isAccessorValue(v)) return .{ .void = {} };
                return v;
            }
            cur = o.prototype;
        }
        return .{ .void = {} };
    }
    if (value == .array) {
        if (index_val == .integer and index_val.integer >= 0) {
            const i: usize = @intCast(index_val.integer);
            if (i < value.array.elements.items.len) {
                const v = value.array.elements.items[i];
                if (v == .hole) return .{ .void = {} };
                return v;
            }
        }
        return .{ .void = {} };
    }
    return .{ .void = {} };
}

fn ocCall(current: ast.Value, receiver: ?ast.Value, args: []ast.Value, env: *Environment, method_name: []const u8) anyerror!ast.Value {
    switch (current) {
        .function, .closure, .generator => return try callFunctionValue(current, args, env, receiver),
        .js_object => {
            if (functionMod.isBoundFunction(current.js_object)) {
                return try callFunctionValue(current, args, env, receiver);
            }
            return error.NotAFunction;
        },
        .object => {
            const recv = receiver orelse return error.NotAFunction;
            const bObjPtr: *const builtinsTypes.BuiltinObjectImpl = @ptrCast(@alignCast(current.object));
            const md = bObjPtr.getMethod(method_name) orelse return error.NotAFunction;
            var list = try std.ArrayList(ast.Value).initCapacity(env.allocator, args.len + 1);
            defer list.deinit(env.allocator);
            try list.append(env.allocator, recv);
            try list.appendSlice(env.allocator, args);
            env.throw_hit = false;
            const res = md(list.items, env);
            if (env.throw_hit) return error.Thrown;
            return switch (res) {
                .value => |v| v,
                .void => .{ .void = {} },
            };
        },
        else => return error.NotAFunction,
    }
}
pub fn callFunctionValue(val: ast.Value, args: []ast.Value, env: *Environment, this_val: ?ast.Value) anyerror!ast.Value {
    switch (val) {
        .function => |fn_ptr| {
            const func_node: *ast.Node = @alignCast(@ptrCast(fn_ptr));
            return try invokeFunctionNode(func_node, args, env, this_val);
        },
        .closure => |cl| {
            const scope: *Environment = @alignCast(@ptrCast(cl.env));
            const func_node: *ast.Node = @alignCast(@ptrCast(cl.func_node));
            return invokeFunctionNode(func_node, args, scope, this_val) catch |err| {
                // The captured scope is not necessarily the caller frame; make
                // the pending JS throw visible where the call was made.
                if (scope.throw_hit) {
                    env.throw_hit = true;
                    env.throw_value = scope.throw_value;
                }
                return err;
            };
        },
        .generator => |gen| {
            return .{ .generator = gen };
        },
        .js_object => |obj| {
            if (promiseMod.isResolver(.{ .js_object = obj })) {
                promiseMod.callResolver(env, obj, args);
                return .{ .void = {} };
            }
            if (functionMod.isBoundFunction(obj)) return try invokeBoundFunction(obj, args, env);
            return error.NotAFunction;
        },
        else => return error.NotAFunction,
    }
}

fn parseProgramNoFree(source: []const u8, env_: *Environment) !struct { statements: []*ast.Node, parser: Parser } {
    var lexer = Lexer.init(source);
    var parser = try Parser.init(&lexer, env_.allocator);
    const statements = try parser.parseProgram();
    return .{ .statements = statements, .parser = parser };
}

fn collectForAwaitValues(env: *Environment, iterable: ast.Value) !*ast.ArrayObject {
    const values = try ast.ArrayObject.init(env.allocator);
    errdefer values.deinit();

    switch (iterable) {
        .array => |arr| {
            for (arr.elements.items) |item| {
                try values.elements.append(env.allocator, try awaitValue(env, item));
            }
        },
        .string => |s| {
            var i: usize = 0;
            while (i < s.len) {
                const cp_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
                try values.elements.append(env.allocator, .{ .string = s[i .. i + cp_len] });
                i += cp_len;
            }
        },
        .generator => |gen| {
            while (true) {
                const next_raw = try evaluateGeneratorNext(gen, env);
                const next_res = try awaitValue(env, next_raw);
                if (next_res != .js_object) break;
                const done = next_res.js_object.properties.get("done") orelse ast.Value{ .boolean = true };
                if (done == .boolean and done.boolean) break;
                const value = next_res.js_object.properties.get("value") orelse ast.Value{ .void = {} };
                try values.elements.append(env.allocator, try awaitValue(env, value));
            }
        },
        .iterator => |iter| {
            while (true) {
                const next_res = iter.next(env.allocator, &env.arrays, &env.objects);
                if (next_res != .js_object) break;
                const done = next_res.js_object.properties.get("done") orelse ast.Value{ .boolean = true };
                if (done == .boolean and done.boolean) break;
                const value = next_res.js_object.properties.get("value") orelse ast.Value{ .void = {} };
                try values.elements.append(env.allocator, try awaitValue(env, value));
            }
        },
        .js_object => |obj| {
            if (obj.properties.get("@@asyncIterator")) |iter_fn| {
                const iterator = try callFunctionValue(iter_fn, &[_]ast.Value{}, env, .{ .js_object = obj });
                if (iterator != .js_object) return error.TypeError;
                try collectForAwaitIterator(env, values, iterator.js_object);
            } else if (obj.properties.get("@@iterator")) |iter_fn| {
                const iterator = try callFunctionValue(iter_fn, &[_]ast.Value{}, env, .{ .js_object = obj });
                if (iterator != .js_object) return error.TypeError;
                try collectForAwaitIterator(env, values, iterator.js_object);
            } else {
                return error.TypeError;
            }
        },
        else => return error.TypeError,
    }
    try env.arrays.append(env.allocator, values);
    return values;
}

fn collectForAwaitIterator(env: *Environment, values: *ast.ArrayObject, iterator: *ast.ObjectValue) !void {
    while (true) {
        const next_fn = iterator.properties.get("next") orelse break;
        const next_raw = try callFunctionValue(next_fn, &[_]ast.Value{}, env, .{ .js_object = iterator });
        const next_res = try awaitValue(env, next_raw);
        if (next_res != .js_object) break;
        const done = next_res.js_object.properties.get("done") orelse ast.Value{ .boolean = true };
        if (done == .boolean and done.boolean) break;
        const value = next_res.js_object.properties.get("value") orelse ast.Value{ .void = {} };
        try values.elements.append(env.allocator, try awaitValue(env, value));
    }
}

fn wrapAsyncGeneratorResult(gen: *GeneratorObject, env: *Environment, value: ast.Value) !ast.Value {
    if (!gen.is_async) return value;
    return promiseMod.createResolved(env, value);
}

pub fn evaluateGeneratorNext(gen: *GeneratorObject, caller_env: *Environment) anyerror!ast.Value {
    const result = evaluateGeneratorNextSync(gen, caller_env) catch |err| {
        if (!gen.is_async) return err;
        const reason = blk: {
            if (caller_env.throw_hit) {
                const value = caller_env.throw_value;
                caller_env.throw_hit = false;
                caller_env.throw_value = .{ .void = {} };
                break :blk value;
            }
            if (gen.gen_env) |env_ptr| {
                const gen_env: *Environment = @alignCast(@ptrCast(env_ptr));
                if (gen_env.throw_hit) {
                    const value = gen_env.throw_value;
                    gen_env.throw_hit = false;
                    gen_env.throw_value = .{ .void = {} };
                    break :blk value;
                }
            }
            break :blk ast.Value{ .string = "Error" };
        };
        gen.done = true;
        if (gen.gen_env) |done_env_ptr| {
            const done_env: *Environment = @alignCast(@ptrCast(done_env_ptr));
            done_env.deinit();
            gen.allocator.destroy(done_env);
            gen.gen_env = null;
        }
        return promiseMod.createRejected(caller_env, reason);
    };
    return wrapAsyncGeneratorResult(gen, caller_env, result);
}

fn evaluateGeneratorNextSync(gen: *GeneratorObject, caller_env: *Environment) anyerror!ast.Value {
    if (gen.done) {
        // Return {value: undefined, done: true}
        var result = ast.ObjectValue.init(caller_env.allocator) catch return .{ .void = {} };
        errdefer result.deinit();
        result.properties.put("value", .{ .void = {} }) catch {};
        result.properties.put("done", .{ .boolean = true }) catch {};
        caller_env.objects.append(caller_env.allocator, result) catch { result.deinit(); return .{ .void = {} }; };
        return .{ .js_object = result };
    }

    const gen_node = @as(*ast.Node, @alignCast(@ptrCast(gen.func_node)));
    const gen_decl = gen_node.GeneratorDeclaration;
    const body = gen_decl.body;

    // Get or create the generator's persistent environment
    var gen_env: *Environment = undefined;
    if (gen.gen_env) |existing_env| {
        gen_env = @alignCast(@ptrCast(existing_env));
        gen_env.is_generator = true;
        gen_env.is_async_generator = gen.is_async;
    } else {
        // First call: create and store the environment
        var new_env = try Environment.init(caller_env.allocator, caller_env);
        new_env.is_generator = true;
        new_env.is_async_generator = gen.is_async;
        for (gen_decl.parameters, 0..) |param, idx| {
            _ = idx;
            try new_env.set(param, .{ .void = {} });
        }
        gen.gen_env = @ptrCast(try caller_env.allocator.create(Environment));
        gen_env = @alignCast(@ptrCast(gen.gen_env.?));
        gen_env.* = new_env;
    }

    // Reset flags for this next() call
    gen_env.return_hit = false;
    gen_env.yield_hit = false;
    // yield_star_* are NOT reset here — managed by the yield* handler

    // Get statements from body
    const statements: []const *ast.Node = switch (body.*) {
        .BlockStatement => |b| b.statements,
        else => &[_]*ast.Node{body},
    };

    var result: ast.Value = .{ .void = {} };
    var returned_value = false;

    // Evaluate statements starting from current IP.
    while (gen.ip < statements.len) {
        const stmt = statements[gen.ip];

        if (stmt.* == .ReturnStatement) {
            const ret_stmt = stmt.ReturnStatement;
            if (ret_stmt.value) |val| {
                result = try evaluate(val, gen_env);
            } else {
                result = .{ .void = {} };
            }
            if (gen.is_async) result = try awaitValue(gen_env, result);
            gen.done = true;
            returned_value = true;
            break;
        }

        // Reset loop-caught flag before evaluating — loops that catch yield will set it.
        gen_env.yield_caught_by_loop = false;
        result = try evaluate(stmt, gen_env);

        // Check if a yield happened. A loop handler may have consumed yield_hit
        // (reset it to false) and set yield_caught_by_loop=true instead, so we
        // save the flag before any resets.
        const yield_caught = gen_env.yield_caught_by_loop;

        if (gen_env.yield_hit or yield_caught) {
            const yielded = gen_env.yield_value;
            gen_env.yield_hit = false;
            gen_env.yield_caught_by_loop = false;

            if (!yield_caught) {
                // Simple yield not inside a loop — advance past this statement.
                gen.ip += 1;
            }
            // else: loop caught the yield — gen.ip stays on the same statement
            // so the next next() re-enters the loop.

            var result_obj = ast.ObjectValue.init(caller_env.allocator) catch return .{ .void = {} };
            errdefer result_obj.deinit();
            result_obj.properties.put("value", yielded) catch {};
            result_obj.properties.put("done", .{ .boolean = false }) catch {};
            caller_env.objects.append(caller_env.allocator, result_obj) catch { result_obj.deinit(); return .{ .void = {} }; };
            return .{ .js_object = result_obj };
        }

        // Statement completed without yielding — check for stale yield_caught_by_loop
        // from nested loops that completed normally, then advance past it.
        gen_env.yield_caught_by_loop = false;
        gen.ip += 1;

        if (gen_env.return_hit) {
            // A return occurred inside the generator — generator is done.
            // result holds the return value.
            if (gen.is_async) result = try awaitValue(gen_env, result);
            gen.done = true;
            // Free gen_env immediately when generator completes
            if (gen.gen_env) |done_env_ptr| {
                const done_env: *Environment = @alignCast(@ptrCast(done_env_ptr));
                done_env.deinit();
                gen.allocator.destroy(done_env);
                gen.gen_env = null;
            }
            var done_result = ast.ObjectValue.init(caller_env.allocator) catch return .{ .void = {} };
            errdefer done_result.deinit();
            done_result.properties.put("value", result) catch {};
            done_result.properties.put("done", .{ .boolean = true }) catch {};
            caller_env.objects.append(caller_env.allocator, done_result) catch { done_result.deinit(); return .{ .void = {} }; };
            return .{ .js_object = done_result };
        }
    }

    // No more statements - generator is done
    if (gen.ip >= statements.len) {
        gen.done = true;
    }

    // Free gen_env immediately when generator completes
    if (gen.gen_env) |done_env_ptr| {
        const done_env: *Environment = @alignCast(@ptrCast(done_env_ptr));
        done_env.deinit();
        gen.allocator.destroy(done_env);
        gen.gen_env = null;
    }

    // Return {value: result, done: true} — result holds the return value if a ReturnStatement was hit
    var done_result = ast.ObjectValue.init(caller_env.allocator) catch return .{ .void = {} };
    errdefer done_result.deinit();
    done_result.properties.put("value", if (returned_value) result else .{ .void = {} }) catch {};
    done_result.properties.put("done", .{ .boolean = true }) catch {};
    caller_env.objects.append(caller_env.allocator, done_result) catch { done_result.deinit(); return .{ .void = {} }; };
    return .{ .js_object = done_result };
}

pub fn evaluateGeneratorReturn(gen: *GeneratorObject, caller_env: *Environment, args: []ast.Value) anyerror!ast.Value {
    const result = try evaluateGeneratorReturnSync(gen, caller_env, args);
    return wrapAsyncGeneratorResult(gen, caller_env, result);
}

fn evaluateGeneratorReturnSync(gen: *GeneratorObject, caller_env: *Environment, args: []ast.Value) anyerror!ast.Value {
    const value = if (args.len > 0) args[0] else @as(ast.Value, .{ .void = {} });

    if (gen.done) {
        var result = ast.ObjectValue.init(caller_env.allocator) catch return .{ .void = {} };
        errdefer result.deinit();
        result.properties.put("value", value) catch {};
        result.properties.put("done", .{ .boolean = true }) catch {};
        caller_env.objects.append(caller_env.allocator, result) catch { result.deinit(); return .{ .void = {} }; };
        return .{ .js_object = result };
    }

    gen.done = true;
    if (gen.gen_env) |env_ptr| {
        const done_env: *Environment = @alignCast(@ptrCast(env_ptr));
        done_env.deinit();
        gen.allocator.destroy(done_env);
        gen.gen_env = null;
    }

    var result = ast.ObjectValue.init(caller_env.allocator) catch return .{ .void = {} };
    errdefer result.deinit();
    result.properties.put("value", value) catch {};
    result.properties.put("done", .{ .boolean = true }) catch {};
    caller_env.objects.append(caller_env.allocator, result) catch { result.deinit(); return .{ .void = {} }; };
    return .{ .js_object = result };
}

pub fn evaluateGeneratorThrow(gen: *GeneratorObject, caller_env: *Environment, args: []ast.Value) anyerror!ast.Value {
    const result = evaluateGeneratorThrowSync(gen, caller_env, args) catch |err| {
        if (!gen.is_async) return err;
        const reason = if (caller_env.throw_hit)
            caller_env.throw_value
        else if (args.len > 0)
            args[0]
        else
            ast.Value{ .string = "Error" };
        caller_env.throw_hit = false;
        caller_env.throw_value = .{ .void = {} };
        return promiseMod.createRejected(caller_env, reason);
    };
    return wrapAsyncGeneratorResult(gen, caller_env, result);
}

fn evaluateGeneratorThrowSync(gen: *GeneratorObject, caller_env: *Environment, args: []ast.Value) anyerror!ast.Value {
    _ = caller_env;
    _ = args;

    if (gen.done) {
        return error.ExceptionThrown;
    }

    gen.done = true;
    if (gen.gen_env) |env_ptr| {
        const done_env: *Environment = @alignCast(@ptrCast(env_ptr));
        done_env.deinit();
        gen.allocator.destroy(done_env);
        gen.gen_env = null;
    }

    return error.ExceptionThrown;
}

/// `eval(code)` — parses and evaluates `code` as Lou source in the current
/// environment. Throws SyntaxError on parse failure.
pub fn predeclareLexicals(env: *Environment, statements: []*ast.Node) void {
    for (statements) |stmt| {
        switch (stmt.*) {
            .LetDeclaration => |v| env.declareLexical(v.name) catch {},
            .ConstantDeclaration => |c| env.declareLexical(c.name) catch {},
            else => {},
        }
    }
}

fn throwTdzValue(env: *Environment, name: []const u8) ast.Value {
    const allocated = std.fmt.allocPrint(env.allocator, "Cannot access '{s}' before initialization", .{name}) catch null;
    if (allocated) |msg| env.owned_strings.append(env.allocator, msg) catch {};
    _ = throwError(env, "ReferenceError", .{ .string = allocated orelse "Cannot access variable before initialization" });
    return .{ .void = {} };
}

pub fn evalFn(args: []ast.Value, env: *builtinsTypes.Environment) builtinsTypes.BuiltinResult {
    if (args.len == 0 or args[0] != .string) return .{ .value = .{ .void = {} } };

    const source = args[0].string;

    var lexer = Lexer.init(source);
    var parser = Parser.init(&lexer, env.allocator) catch return .{ .value = .{ .void = {} } };

    const program = parser.parseProgram() catch {
        parser.deinit();
        _ = throwError(env, "SyntaxError", .{ .string = "eval parse error" });
        return .{ .void = {} };
    };

    // Functions created by eval outlive the call, so the parser arena (and
    // therefore every AST node) must stay alive until the program ends.
    // eval() writes into a throwaway lexical scope: `var` and function
    // declarations hoist to the caller, while `let`/`const` stay local.
    const caller = @as(*Environment, @ptrCast(env));
    const root_env = caller.root();
    root_env.module_arenas.append(root_env.allocator, parser.arena) catch {};

    var eval_env = Environment.initBlock(caller.allocator, caller) catch {
        return .{ .value = .{ .void = {} } };
    };
    defer eval_env.deinit();

    var result: ast.Value = .{ .void = {} };
    @setEvalBranchQuota(2000);
    for (program) |stmt| {
        result = evaluate(stmt, &eval_env) catch {
            if (eval_env.throw_hit) {
                caller.throw_hit = true;
                caller.throw_value = eval_env.throw_value;
                eval_env.throw_hit = false;
            }
            return .{ .value = .{ .void = {} } };
        };
    }
    if (eval_env.throw_hit) {
        caller.throw_hit = true;
        caller.throw_value = eval_env.throw_value;
        eval_env.throw_hit = false;
    }

    return .{ .value = result };
}

test "let binding stays in TDZ until initialized" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try env_.declareLexical("x");
    try std.testing.expect(env_.isUninitialized("x"));
    try std.testing.expectError(error.Thrown, parseAndEvaluate("x", &env_));
    try std.testing.expect(env_.throw_hit);
    try std.testing.expectEqualStrings("ReferenceError", env_.throw_value.js_object.properties.get("@@subtype").?.string);
    env_.throw_hit = false;

    try env_.setLet("x", .{ .integer = 5 });
    try std.testing.expect(!env_.isUninitialized("x"));
    const value = try parseAndEvaluate("x", &env_);
    try std.testing.expectEqual(@as(i64, 5), value.integer);
}

test "constant binding can initialize a predeclared slot" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try env_.declareLexical("c");
    try env_.setConstant("c", .{ .integer = 7 });
    try std.testing.expect(!env_.isUninitialized("c"));
    try std.testing.expect(env_.isConstant("c"));
    try std.testing.expectEqual(@as(i64, 7), env_.get("c").?.integer);
}

test "evalFn scopes let but keeps var in caller" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    var args = [_]ast.Value{.{ .string = "var a = 1; let b = 2; b" }};
    const result = evalFn(&args, &env_);
    try std.testing.expect(result == .value);
    try std.testing.expectEqual(@as(i64, 2), result.value.integer);
    try std.testing.expect(env_.get("a") != null);
    try std.testing.expect(env_.get("b") == null);
}

test "evalFn propagates thrown errors" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    var args = [_]ast.Value{.{ .string = "throw new Error(\"boom\")" }};
    _ = evalFn(&args, &env_);
    try std.testing.expect(env_.throw_hit);
    try std.testing.expect(env_.throw_value == .js_object);
}

// --- Environment tests ---

test "Environment - set and get" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try env_.set("x", .{ .integer = 42 });
    const val = env_.get("x");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 42), val.?.integer);
}

test "Environment - get returns null for undefined" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const val = env_.get("undefined_var");
    try std.testing.expect(val == null);
}

test "Environment - outer scope lookup" {
    const allocator = std.testing.allocator;
    var outer = try Environment.init(allocator, null);
    defer outer.deinit();
    try outer.set("x", .{ .integer = 10 });

    var inner = try Environment.init(allocator, &outer);
    defer inner.deinit();

    const val = inner.get("x");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 10), val.?.integer);
}

test "Environment - setConstant" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try env_.setConstant("PI", .{ .float = 3.14 });
    const val = env_.get("PI");
    try std.testing.expect(val != null);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), val.?.float, 0.001);
}

test "Environment - constant reassignment fails" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try env_.setConstant("PI", .{ .float = 3.14 });
    const result = env_.set("PI", .{ .float = 3.14159 });
    try std.testing.expectError(error.ConstantReassignment, result);
}

test "Environment - isConstant" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try std.testing.expect(!env_.isConstant("x"));
    try env_.setConstant("x", .{ .integer = 1 });
    try std.testing.expect(env_.isConstant("x"));
}

// --- Literal evaluation tests ---

test "evaluate integer literal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("42", &env_);
    try std.testing.expectEqual(@as(i64, 42), result.integer);
}

test "evaluate float literal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("3.14", &env_);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), result.float, 0.001);
}

test "evaluate string literal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("'hello'", &env_);
    try std.testing.expectEqualStrings("hello", result.string);
}

test "evaluate boolean true" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("true", &env_);
    try std.testing.expect(result.boolean);
}

test "evaluate boolean false" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("false", &env_);
    try std.testing.expect(!result.boolean);
}

// --- Binary expression arithmetic tests ---

test "evaluate integer addition" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("3 + 4", &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 7), result.integer);
}

test "evaluate integer subtraction" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("10 - 3", &env_);
    try std.testing.expectEqual(@as(i64, 7), result.integer);
}

test "evaluate integer multiplication" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("6 * 7", &env_);
    try std.testing.expectEqual(@as(i64, 42), result.integer);
}

test "evaluate integer division" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("10 / 2", &env_);
    try std.testing.expect(result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), result.float, 0.001);
}

test "evaluate integer modulo" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("5 % 2", &env_);
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "evaluate float arithmetic" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("1.5 + 2.5", &env_);
    try std.testing.expect(result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), result.float, 0.001);
}

test "evaluate operator precedence" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("2 + 3 * 4", &env_);
    try std.testing.expectEqual(@as(i64, 14), result.integer);
}

// --- Comparison operator tests ---

test "evaluate less than" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("3 < 5", &env_);
    try std.testing.expect(result == .boolean);
    try std.testing.expect(result.boolean);
}

test "evaluate greater than or equal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("5 >= 5", &env_);
    try std.testing.expect(result.boolean);
}

test "evaluate equality" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("42 == 42", &env_);
    try std.testing.expect(result.boolean);
}

test "evaluate not equal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("1 != 2", &env_);
    try std.testing.expect(result.boolean);
}

// --- Logical operator tests ---

test "evaluate logical and - true" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("true && true", &env_);
    try std.testing.expect(result == .boolean);
    try std.testing.expect(result.boolean);
}

test "evaluate logical and - false" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("true && false", &env_);
    try std.testing.expect(!result.boolean);
}

test "evaluate logical or - true" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("false || true", &env_);
    try std.testing.expect(result.boolean);
}

test "evaluate logical or - false" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("false || false", &env_);
    try std.testing.expect(!result.boolean);
}

test "evaluate logical not" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("!true", &env_);
    try std.testing.expect(!result.boolean);
}

// --- Bitwise operator tests ---

test "evaluate bitwise and" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("5 & 3", &env_);
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "evaluate bitwise or" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("5 | 3", &env_);
    try std.testing.expectEqual(@as(i64, 7), result.integer);
}

test "evaluate bitwise xor" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("5 ^ 3", &env_);
    try std.testing.expectEqual(@as(i64, 6), result.integer);
}

test "evaluate bitwise not" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("~5", &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, -6), result.integer);
}

test "evaluate left shift" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("1 << 3", &env_);
    try std.testing.expectEqual(@as(i64, 8), result.integer);
}

test "evaluate right shift" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("8 >> 1", &env_);
    try std.testing.expectEqual(@as(i64, 4), result.integer);
}

// --- Assignment tests ---

test "evaluate variable declaration and identifier" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 10", &env_);
    const result = try parseAndEvaluate("x", &env_);
    try std.testing.expectEqual(@as(i64, 10), result.integer);
}

test "evaluate constant declaration" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("const PI = 3.14", &env_);
    const result = try parseAndEvaluate("PI", &env_);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), result.float, 0.001);
}

test "evaluate reassignment" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 1", &env_);
    _ = try parseAndEvaluateProgram("x = 5", &env_);
    const result = try parseAndEvaluate("x", &env_);
    try std.testing.expectEqual(@as(i64, 5), result.integer);
}

// --- Compound assignment tests ---

test "evaluate plus assign" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 10", &env_);
    const result = try parseAndEvaluateProgram("x += 5", &env_);
    try std.testing.expectEqual(@as(i64, 15), result.integer);
}

test "evaluate minus assign" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 10", &env_);
    const result = try parseAndEvaluateProgram("x -= 3", &env_);
    try std.testing.expectEqual(@as(i64, 7), result.integer);
}

test "evaluate multiply assign" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 4", &env_);
    const result = try parseAndEvaluateProgram("x *= 3", &env_);
    try std.testing.expectEqual(@as(i64, 12), result.integer);
}

test "evaluate modulo assign" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 10", &env_);
    const result = try parseAndEvaluateProgram("x %= 3", &env_);
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

// --- Nullish coalescing tests ---

test "evaluate nullish coalescing - nullish triggers fallback" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try env_.set("x", .{ .void = {} });
    const result = try parseAndEvaluate("x ?? 42", &env_);
    try std.testing.expectEqual(@as(i64, 42), result.integer);
}

test "evaluate nullish coalescing - non-nullish keeps left" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("0 ?? 99", &env_);
    try std.testing.expectEqual(@as(i64, 0), result.integer);
}

test "evaluate nullish coalescing - zero integer keeps left" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("10 ?? 42", &env_);
    try std.testing.expectEqual(@as(i64, 10), result.integer);
}

// --- valuesEqual tests ---

test "valuesEqual - integer equality" {
    const left = ast.Value{ .integer = 42 };
    const right = ast.Value{ .integer = 42 };
    try std.testing.expect(valuesEqual(left, right));
}

test "valuesEqual - integer inequality" {
    const left = ast.Value{ .integer = 42 };
    const right = ast.Value{ .integer = 99 };
    try std.testing.expect(!valuesEqual(left, right));
}

test "valuesEqual - integer float cross comparison" {
    const left = ast.Value{ .integer = 42 };
    const right = ast.Value{ .float = 42.0 };
    try std.testing.expect(valuesEqual(left, right));
}

test "valuesEqual - string equality" {
    const left = ast.Value{ .string = "hello" };
    const right = ast.Value{ .string = "hello" };
    try std.testing.expect(valuesEqual(left, right));
}

test "valuesEqual - string inequality" {
    const left = ast.Value{ .string = "hello" };
    const right = ast.Value{ .string = "world" };
    try std.testing.expect(!valuesEqual(left, right));
}

test "valuesEqual - boolean equality" {
    try std.testing.expect(valuesEqual(.{ .boolean = true }, .{ .boolean = true }));
    try std.testing.expect(!valuesEqual(.{ .boolean = true }, .{ .boolean = false }));
}

test "valuesEqual - void equality" {
    try std.testing.expect(valuesEqual(.{ .void = {} }, .{ .void = {} }));
}

test "valuesEqual - different types" {
    try std.testing.expect(!valuesEqual(.{ .integer = 42 }, .{ .string = "42" }));
    try std.testing.expect(!valuesEqual(.{ .float = 42.0 }, .{ .boolean = true }));
}

// --- Block statement tests ---

test "evaluate block statement" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram("{ 42 }", &env_);
    try std.testing.expectEqual(@as(i64, 42), result.integer);
}

// --- If statement tests ---

test "evaluate if statement - true branch" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const if_result = try parseAndEvaluateProgram("if (true) { 100 }", &env_);
    try std.testing.expectEqual(@as(i64, 100), if_result.integer);
}

test "evaluate if else statement - false branch" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram("if (false) { 100 } else { 200 }", &env_);
    try std.testing.expectEqual(@as(i64, 200), result.integer);
}

test "evaluate if statement - no else returns 0" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram("if (false) { 100 }", &env_);
    try std.testing.expect(result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.float, 0.001);
}

// --- While loop tests ---

test "evaluate while loop" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var i = 0", &env_);
    _ = try parseAndEvaluateProgram("var sum = 0", &env_);
    _ = try parseAndEvaluateProgram("while (i < 5) { sum += i; i += 1 }", &env_);
    const result = try parseAndEvaluate("sum", &env_);
    const result_f: f64 = switch (result) {
        .integer => |v| @floatFromInt(v),
        .float => |v| v,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), result_f, 0.001);
}

test "evaluate do while loop" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var i = 0", &env_);
    _ = try parseAndEvaluateProgram("var sum = 0", &env_);
    _ = try parseAndEvaluateProgram("do { sum += i; i += 1 } while (i < 5)", &env_);
    const result = try parseAndEvaluate("sum", &env_);
    const result_f: f64 = switch (result) {
        .integer => |v| @floatFromInt(v),
        .float => |v| v,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), result_f, 0.001);
}

test "evaluate do while loop - executes at least once" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var ran = false", &env_);
    _ = try parseAndEvaluateProgram("do { ran = true } while (false)", &env_);
    const result = try parseAndEvaluate("ran", &env_);
    try std.testing.expect(result == .boolean);
    try std.testing.expect(result.boolean);
}

// --- For loop tests ---

test "evaluate for loop - simple" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var sum = 0", &env_);
    _ = try parseAndEvaluateProgram("for (var j = 1; j < 6; j = j + 1) { sum = sum + j }", &env_);
    const result = try parseAndEvaluate("sum", &env_);
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), result.float, 0.001);
}

test "evaluate for in loop" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var obj = { a: 1, b: 2, c: 3 }", &env_);
    _ = try parseAndEvaluateProgram("var keys = []", &env_);
    _ = try parseAndEvaluateProgram("for (var k in obj) { keys.push(k) }", &env_);
    const result = try parseAndEvaluate("keys", &env_);

    try std.testing.expect(result == .array);
    try std.testing.expectEqual(@as(usize, 3), result.array.elements.items.len);
    try std.testing.expectEqualStrings("a", result.array.elements.items[0].string);
    try std.testing.expectEqualStrings("b", result.array.elements.items[1].string);
    try std.testing.expectEqualStrings("c", result.array.elements.items[2].string);
}

test "evaluate for in loop with const" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var obj = { x: 10, y: 20 }", &env_);
    _ = try parseAndEvaluateProgram("var keys = []", &env_);
    _ = try parseAndEvaluateProgram("for (const k in obj) { keys.push(k) }", &env_);
    const result = try parseAndEvaluate("keys", &env_);

    try std.testing.expect(result == .array);
    try std.testing.expectEqual(@as(usize, 2), result.array.elements.items.len);
    try std.testing.expectEqualStrings("x", result.array.elements.items[0].string);
    try std.testing.expectEqualStrings("y", result.array.elements.items[1].string);
}

test "evaluate for in loop on array" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var arr = [10, 20, 30]", &env_);
    _ = try parseAndEvaluateProgram("var indices = []", &env_);
    _ = try parseAndEvaluateProgram("for (var idx in arr) { indices.push(idx) }", &env_);
    const result = try parseAndEvaluate("indices", &env_);

    try std.testing.expect(result == .array);
    try std.testing.expectEqual(@as(usize, 3), result.array.elements.items.len);
    try std.testing.expectEqualStrings("0", result.array.elements.items[0].string);
    try std.testing.expectEqualStrings("1", result.array.elements.items[1].string);
    try std.testing.expectEqualStrings("2", result.array.elements.items[2].string);
}

// --- Function tests ---

test "evaluate function declaration and call" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result_struct = try parseProgramNoFree("function add(a, b) { return a + b }", &env_);
    var parser = result_struct.parser;
    defer parser.deinit();
    _ = try evaluate(result_struct.statements[0], &env_);
    const result = try parseAndEvaluate("add(3, 4)", &env_);
    try std.testing.expectEqual(@as(i64, 7), result.integer);
}

test "evaluate arrow function" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result_struct = try parseProgramNoFree("const double = (x) => x * 2", &env_);
    var parser = result_struct.parser;
    defer parser.deinit();
    _ = try evaluate(result_struct.statements[0], &env_);
    const result = try parseAndEvaluate("double(5)", &env_);
    try std.testing.expectEqual(@as(i64, 10), result.integer);
}

// --- Array tests ---

test "evaluate array literal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("[1, 2, 3]", &env_);
    try std.testing.expect(result == .array);
    try std.testing.expectEqual(@as(usize, 3), result.array.elements.items.len);
}

test "evaluate array index" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var arr = [10, 20, 30]", &env_);
    const result = try parseAndEvaluate("arr[1]", &env_);
    try std.testing.expectEqual(@as(i64, 20), result.integer);
}

// --- let vs var block scoping tests ---

test "let is block-scoped - not visible outside block" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("{ let x = 42 }", &env_);
    const result = env_.get("x");
    try std.testing.expect(result == null);
}

test "var leaks out of block" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("{ var x = 42 }", &env_);
    const result = env_.get("x");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 42), result.?.integer);
}

test "let shadows var in block" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 1", &env_);
    const result = try parseAndEvaluateProgram("{ let x = 2; x }", &env_);
    try std.testing.expectEqual(@as(i64, 2), result.integer);

    const outer = env_.get("x");
    try std.testing.expect(outer != null);
    try std.testing.expectEqual(@as(i64, 1), outer.?.integer);
}

test "var reassignment inside block updates outer" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 1", &env_);
    _ = try parseAndEvaluateProgram("{ x = 99 }", &env_);
    const result = env_.get("x");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 99), result.?.integer);
}

test "let re-declaration in same block fails" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = parseAndEvaluateProgram("{ let x = 1; let x = 2 }", &env_);
    try std.testing.expectError(error.LetRedeclaration, result);
}

test "let in nested blocks" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("let x = 1", &env_);
    const result = try parseAndEvaluateProgram("{ let x = 2; { let x = 3; x } }", &env_);
    try std.testing.expectEqual(@as(i64, 3), result.integer);

    const outer = env_.get("x");
    try std.testing.expect(outer != null);
    try std.testing.expectEqual(@as(i64, 1), outer.?.integer);
}

test "var in nested block updates function scope" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 1", &env_);
    _ = try parseAndEvaluateProgram("{ { var x = 99 } }", &env_);
    const result = env_.get("x");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 99), result.?.integer);
}

test "findIndex with inline arrow function" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram(
        \\const arr = [5, 12, 8, 130, 44];
        \\arr.findIndex((x) => x > 13)
    , &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 3), result.integer);
}

test "findIndex with inline function - no match" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram(
        \\const arr = [1, 2, 3];
        \\arr.findIndex((x) => x > 100)
    , &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, -1), result.integer);
}

test "filter with inline arrow function" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram(
        \\const arr = [3, -1, 1, 4];
        \\arr.filter((num) => num > 0)
    , &env_);
    try std.testing.expect(result == .array);
    try std.testing.expectEqual(@as(usize, 3), result.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 3), result.array.elements.items[0].integer);
}

test "findIndex with arr param" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram(
        \\const arr = [3, 1, 4];
        \\arr.findIndex((num, idx, a) => num > a[1])
    , &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 0), result.integer);
}

test "findIndex with arr.length" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram(
        \\const arr = [3, 1, 4];
        \\arr.findIndex((num, idx, a) => idx < a.length - 1)
    , &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 0), result.integer);
}

test "findIndex with block body return" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram(
        \\const arr = [1, 3, 2];
        \\arr.findIndex((x) => {
        \\  return x > 2;
        \\})
    , &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "findIndex with if return block" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram(
        \\const arr = [1, 3, 2];
        \\arr.findIndex((x) => {
        \\  if (x > 2) return true;
        \\  return false;
        \\})
    , &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "findIndex simple trough" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram(
        \\const arr = [3, 1, 4];
        \\arr.findIndex((num, idx, a) => {
        \\  if (idx > 0 && num >= a[idx - 1]) return false;
        \\  if (idx < a.length - 1 && num >= a[idx + 1]) return false;
        \\  return true;
        \\})
    , &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "filter + findIndex chained with inline arrow functions" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram(
        \\const numbers = [3, -1, 1, 4, 1, 5, 9, 2, 6];
        \\numbers
        \\  .filter((num) => num > 0)
        \\  .findIndex((num, idx, arr) => {
        \\    if (idx > 0 && num >= arr[idx - 1]) return false;
        \\    if (idx < arr.length - 1 && num >= arr[idx + 1]) return false;
        \\    return true;
        \\  })
    , &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "TypeError thrown when calling Map.size as function" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try std.testing.expectError(error.Thrown, parseAndEvaluateProgram(
        \\const m = new Map();
        \\m.set("a", 1);
        \\m.size();
    , &env_));
}

test "TypeError thrown when calling Set.size as function" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try std.testing.expectError(error.Thrown, parseAndEvaluateProgram(
        \\const s = new Set();
        \\s.add(1);
        \\s.size();
    , &env_));
}

test "TypeError thrown when calling Array.length as function" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try std.testing.expectError(error.Thrown, parseAndEvaluateProgram(
        \\const arr = [1, 2, 3];
        \\arr.length();
    , &env_));
}

test "TypeError thrown when calling String.length as function" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try std.testing.expectError(error.Thrown, parseAndEvaluateProgram(
        \\const str = "hi";
        \\str.length();
    , &env_));
}

test "looseValuesEqual - number/string/bool coercion" {
    const allocator = std.testing.allocator;
    var bigints = std.ArrayList(*ast.BigIntValue).initCapacity(allocator, 0) catch unreachable;
    defer bigints.deinit(allocator);

    try std.testing.expect(looseValuesEqual(allocator, &bigints, .{ .integer = 0 }, .{ .string = "" }));
    try std.testing.expect(looseValuesEqual(allocator, &bigints, .{ .integer = 0 }, .{ .string = "0" }));
    try std.testing.expect(looseValuesEqual(allocator, &bigints, .{ .boolean = false }, .{ .string = "" }));
    try std.testing.expect(looseValuesEqual(allocator, &bigints, .{ .integer = 1 }, .{ .float = 1.0 }));
    try std.testing.expect(!looseValuesEqual(allocator, &bigints, .{ .integer = 1 }, .{ .string = "2" }));
    try std.testing.expect(!looseValuesEqual(allocator, &bigints, .{ .null = {} }, .{ .integer = 0 }));
}

/// Canonical array index key: decimal digits only, no leading zeros ("0" is valid).
fn arrayKeyIndex(key: []const u8) ?usize {
    if (key.len == 0) return null;
    if (key.len > 1 and key[0] == '0') return null;
    for (key) |ch| {
        if (ch < '0' or ch > '9') return null;
    }
    return std.fmt.parseInt(usize, key, 10) catch null;
}

test "in operator - own properties, arrays and holes" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try std.testing.expect((try parseAndEvaluate("'a' in { a: 1 }", &env_)).boolean);
    try std.testing.expect(!(try parseAndEvaluate("'z' in { a: 1 }", &env_)).boolean);
    try std.testing.expect((try parseAndEvaluate("0 in [10, 20]", &env_)).boolean);
    try std.testing.expect(!(try parseAndEvaluate("2 in [10, 20]", &env_)).boolean);
    try std.testing.expect(!(try parseAndEvaluate("0 in [, 1]", &env_)).boolean);
    try std.testing.expect((try parseAndEvaluate("1 in [, 1]", &env_)).boolean);
    try std.testing.expect(!(try parseAndEvaluate("'01' in [1, 2]", &env_)).boolean);
    try std.testing.expect((try parseAndEvaluate("'length' in [1, 2]", &env_)).boolean);
}

test "instanceof operator - builtins and primitives" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try std.testing.expect((try parseAndEvaluate("[] instanceof Array", &env_)).boolean);
    try std.testing.expect((try parseAndEvaluate("[] instanceof Object", &env_)).boolean);
    try std.testing.expect((try parseAndEvaluate("({}) instanceof Object", &env_)).boolean);
    try std.testing.expect(!(try parseAndEvaluate("'hi' instanceof String", &env_)).boolean);
    try std.testing.expect(!(try parseAndEvaluate("null instanceof Object", &env_)).boolean);
    try std.testing.expect(!(try parseAndEvaluate("undefined instanceof Object", &env_)).boolean);
}

test "typeof Object.prototype method is function" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();
    env_.object_prototype = try objectPrototypeMod.createObjectPrototype(allocator, &env_.objects);

    const result = try parseAndEvaluate("typeof ({}).toString", &env_);
    try std.testing.expect(result == .string);
    try std.testing.expectEqualStrings("function", result.string);
}

test "Date objects coerce to timestamps in arithmetic" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("new Date(1000) - new Date(500)", &env_);
    try std.testing.expect(result == .float);
    try std.testing.expectEqual(@as(f64, 500), result.float);
}

test "object literal getters and setters" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate(
        \\(() => { const o = { _v: 1, get v() { return this._v; }, set v(n) { this._v = n * 2; } }; o.v = 5; return o.v; })()
    , &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 10), result.integer);
}

test "default parameter values" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    // Missing argument falls back to the default expression.
    const r1 = try parseAndEvaluate("(function add(a, b = 5) { return a + b; })(3)", &env_);
    try std.testing.expectEqual(@as(i64, 8), r1.integer);

    // Explicit undefined still uses the default; earlier params are visible.
    const r2 = try parseAndEvaluate(
        \\(function f(x = 1, y = x * 2) { return y; })(undefined)
    , &env_);
    try std.testing.expectEqual(@as(i64, 2), r2.integer);
}

test "template literal interpolation" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { const x = 2; return `v=${x}-${1 + 2}-ok`; })()", &env_);
    try std.testing.expect(r == .string);
    try std.testing.expectEqualStrings("v=2-3-ok", r.string);
}

test "Boolean wrapper objects" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { const b = new Boolean(false); return typeof b + ':' + b.valueOf() + ':' + b.toString(); })()", &env_);
    try std.testing.expect(r == .string);
    try std.testing.expectEqualStrings("object:false:false", r.string);

    const truthy = try parseAndEvaluate("(new Boolean(false)) ? 'truthy' : 'falsy'", &env_);
    try std.testing.expect(truthy == .string);
    try std.testing.expectEqualStrings("truthy", truthy.string);
}

test "Function.prototype call, apply and bind" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { function f(a, b) { return a + b + (this.n || 0); } const o = { n: 10 }; const g = f.bind(o, 1); return f.call(o, 2, 3) + '/' + f.apply(o, [4, 5]) + '/' + g(2); })()", &env_);
    try std.testing.expect(r == .string);
    try std.testing.expectEqualStrings("15/19/13", r.string);
}

test "object literal method shorthand" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { const o = { n: 4, m() { return this.n + 3; } }; return o.m(); })()", &env_);
    try std.testing.expectEqual(@as(i64, 7), r.integer);
}

test "custom iterable for-of respects @@iterator" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { const it = {}; it[\"@@iterator\"] = function () { let i = 0; return { next() { if (i < 3) { return { value: i++, done: false }; } return { done: true }; } }; }; let s = 0; for (const x of it) { s += x; } return s; })()", &env_);
    try std.testing.expectEqual(@as(i64, 3), r.integer);
}

test "nested block return aborts the enclosing function" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(function f() { if (true) { return 1; } return 2; })()", &env_);
    try std.testing.expectEqual(@as(i64, 1), r.integer);
}

test "closures keep the function scope alive when created inside a block" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { function make() { let i = 0; return { n() { if (i < 3) { return { value: i, done: false }; } return { done: true }; } }; } const it = make(); return it.n().value; })()", &env_);
    try std.testing.expectEqual(@as(i64, 0), r.integer);
}

test "regex literals evaluate to RegExp values" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const t = try parseAndEvaluate("typeof /hello/gi", &env_);
    try std.testing.expectEqualStrings("object", t.string);

    const hit = try parseAndEvaluate("/hello/gi.test(\"HELLO\")", &env_);
    try std.testing.expect(hit.boolean);

    const src = try parseAndEvaluate("/ab+c/.source", &env_);
    try std.testing.expectEqualStrings("ab+c", src.string);

    const flags = try parseAndEvaluate("/(?:)/gimsuy.flags", &env_);
    try std.testing.expectEqualStrings("gimsuy", flags.string);
}

test "regexp lastIndex is writable and division still divides" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { const re = /a/g; re.lastIndex = 2; return re.lastIndex; })()", &env_);
    try std.testing.expectEqual(@as(i64, 2), r.integer);

    const d = try parseAndEvaluate("6 / 3", &env_);
    try std.testing.expectEqual(@as(f64, 2.0), d.float);
}
test "WeakRef rejects primitives and deref returns the target" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const ok = try parseAndEvaluate("(() => { const o = { n: 1 }; const w = new WeakRef(o); return w.deref() === o; })()", &env_);
    try std.testing.expect(ok.boolean);

    const num = try parseAndEvaluate("(() => { try { new WeakRef(1); return \"no\"; } catch (e) { return e instanceof TypeError ? \"yes\" : \"other\"; } })()", &env_);
    try std.testing.expectEqualStrings("yes", num.string);

    const none = try parseAndEvaluate("(() => { try { new WeakRef(); return \"no\"; } catch (e) { return e instanceof TypeError ? \"yes\" : \"other\"; } })()", &env_);
    try std.testing.expectEqualStrings("yes", none.string);
}
test "multiple declarators share the enclosing scope" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { const a = 10, b = 2; return a / b; })()", &env_);
    try std.testing.expectEqual(@as(f64, 5.0), r.float);

    const r2 = try parseAndEvaluate("(() => { let x = 3, y = 4; return x * y; })()", &env_);
    try std.testing.expectEqual(@as(i64, 12), r2.integer);

    const r3 = try parseAndEvaluate("(() => { { let i = 7, j = 8; return i + j; } })()", &env_);
    try std.testing.expectEqual(@as(i64, 15), r3.integer);
}

test "regex patterns work in replace and split" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const rep = try parseAndEvaluate("\"a1b2\".replace(/[0-9]/g, \"x\")", &env_);
    try std.testing.expectEqualStrings("axbx", rep.string);

    const cap = try parseAndEvaluate("\"2024-11\".replace(/(\\d+)/, \"<$1>\")", &env_);
    try std.testing.expectEqualStrings("<2024>-11", cap.string);

    const sp = try parseAndEvaluate("\"a,b\".split(/,/)", &env_);
    try std.testing.expect(sp == .array);
    try std.testing.expectEqual(@as(usize, 2), sp.array.elements.items.len);
    try std.testing.expectEqualStrings("a", sp.array.elements.items[0].string);
    try std.testing.expectEqualStrings("b", sp.array.elements.items[1].string);
}

test "throws inside iteration callbacks reach the outer catch" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { try { [1].forEach(function () { throw new Error(\"cb\"); }); return \"no\"; } catch (e) { return e.message; } })()", &env_);
    try std.testing.expectEqualStrings("cb", r.string);
}

test "JSON.stringify orders integer keys first" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("JSON.stringify({b: 1, 0: 2})", &env_);
    try std.testing.expectEqualStrings("{\"0\":2,\"b\":1}", r.string);
}

test "reserved words are valid property names after a dot" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { const o = { x: 1 }; o.delete = 2; o.new = 3; return o.delete + o.new; })()", &env_);
    try std.testing.expectEqual(@as(i64, 5), r.integer);
}

test "class methods bind rest parameters and return arrays safely" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { class C { constructor(first, ...rest) { this.first = first; this.rest = rest; } } const c = new C(1, 2, 3); return c.rest.length + c.first; })()", &env_);
    try std.testing.expectEqual(@as(i64, 3), r.integer);
}

test "class inheritance calls super and dispatches overridden methods" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { class A { constructor(x) { this.x = x; } label() { return \"A\" + this.x; } } class B extends A { constructor(x) { super(x); } label() { return super.label() + \"B\"; } } const b = new B(7); return b.label() + b.x; })()", &env_);
    try std.testing.expectEqualStrings("A7B7", r.string);
}

test "class getters and static members resolve through the prototype chain" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { class C { #n = 2; static twice(x) { return x * 2; } get value() { return this.#n; } set value(v) { this.#n = v; } } const c = new C(); c.value = 5; return C.twice(c.value); })()", &env_);
    try std.testing.expectEqual(@as(i64, 10), r.integer);
}
test "optional chaining short-circuits and preserves method this" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const r = try parseAndEvaluate("(() => { const o = null; const t = { v: 1, get: function () { return this.v; } }; return [o?.a?.b, t.get?.(), t?.get()].join(\",\"); })()", &env_);
    try std.testing.expectEqualStrings(",1,1", r.string);
}

test "async functions await values and resolve chained promises" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var result = 0; var chained = 0; async function f() { result = await Promise.resolve(41); return result + 1; } f().then(v => { chained = v; });",
        &env_,
    );
    try std.testing.expectEqual(@as(i64, 41), (try parseAndEvaluate("result", &env_)).integer);
    try std.testing.expectEqual(@as(i64, 42), (try parseAndEvaluate("chained", &env_)).integer);
}

test "async throw rejects and catch handlers observe the reason" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var state = { message: \"\" }; async function boom() { throw new Error(\"nope\"); } boom().catch(e => { state.message = e.message; });",
        &env_,
    );
    const value = try parseAndEvaluate("state.message", &env_);
    try std.testing.expectEqualStrings("nope", value.string);
}

test "Promise constructor and Promise.all settle queued reactions" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var values = \"\"; new Promise(resolve => resolve(5)).then(v => { values = values + v; }); Promise.all([Promise.resolve(1), 2]).then(v => { values = values + \":\" + v.join(\",\"); });",
        &env_,
    );
    const value = try parseAndEvaluate("values", &env_);
    try std.testing.expectEqualStrings("5:1,2", value.string);
}

test "Promise.all waits for deferred resolutions" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var resolveLater = null; var out = 0; const p = new Promise(r => { resolveLater = r; }); Promise.all([p]).then(v => { out = v[0]; }); resolveLater(8);",
        &env_,
    );
    try std.testing.expectEqual(@as(i64, 8), (try parseAndEvaluate("out", &env_)).integer);
}

test "Promise.withResolvers settles promises independently" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var out = ''; const first = Promise.withResolvers(); const second = Promise.withResolvers(); first.resolve('a'); first.reject('ignored'); second.reject('b'); Promise.all([first.promise, second.promise.catch(e => 'caught:' + e)]).then(v => { out = v.join(','); });",
        &env_,
    );
    try std.testing.expectEqualStrings("a,caught:b", (try parseAndEvaluate("out", &env_)).string);
}

test "Promise.withResolvers adopts promises and exposes functions" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var out = ''; var kinds = ''; const inner = Promise.withResolvers(); const outer = Promise.withResolvers(); kinds = typeof outer.resolve + typeof outer.reject; outer.resolve(inner.promise); inner.resolve('adopted'); outer.promise.then(v => { out = v; });",
        &env_,
    );
    try std.testing.expectEqualStrings("functionfunction", (try parseAndEvaluate("kinds", &env_)).string);
    try std.testing.expectEqualStrings("adopted", (try parseAndEvaluate("out", &env_)).string);
}

test "async generator next returns a Promise" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var value = 0; var wasPromise = false; async function* g() { yield 1; yield 2; } const p = g().next(); wasPromise = p instanceof Promise; p.then(r => { value = r.value; });",
        &env_,
    );
    try std.testing.expect((try parseAndEvaluate("wasPromise", &env_)).boolean);
    try std.testing.expectEqual(@as(i64, 1), (try parseAndEvaluate("value", &env_)).integer);
}

test "for await consumes async generators" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var out = ''; async function* g() { yield 'a'; yield 'b'; } async function main() { for await (const value of g()) { out += value; } } main();",
        &env_,
    );
    try std.testing.expectEqualStrings("ab", (try parseAndEvaluate("out", &env_)).string);
}

test "async generators return undefined after natural completion" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var out = 'bad'; async function* g() { yield 1; } async function main() { const it = g(); await it.next(); const r = await it.next(); if (r.done && r.value === undefined) out = 'ok'; } main();",
        &env_,
    );
    try std.testing.expectEqualStrings("ok", (try parseAndEvaluate("out", &env_)).string);
}

test "async generators await return values" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var out = 'bad'; async function* g() { return Promise.resolve('done'); } async function main() { const r = await g().next(); if (r.done && r.value === 'done') out = 'ok'; } main();",
        &env_,
    );
    try std.testing.expectEqualStrings("ok", (try parseAndEvaluate("out", &env_)).string);
}

test "async generator rejected yield rejects next" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try parseEvaluateAndDrain(
        "var out = 'bad'; async function* g() { yield Promise.reject('boom'); } async function main() { try { await g().next(); } catch (error) { out = error; } } main();",
        &env_,
    );
    try std.testing.expectEqualStrings("boom", (try parseAndEvaluate("out", &env_)).string);
}

test "generator for-let loops resume with the advanced binding" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate(
        "(() => { function* g() { for (let i = 1; i <= 3; i++) yield i; } let out = ''; for (const n of g()) out += n; return out; })()",
        &env_,
    );
    try std.testing.expectEqualStrings("123", result.string);
}

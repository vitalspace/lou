const std = @import("std");
const ast = @import("ast.zig");
const builtinsTypes = @import("./types/types.zig");
const env_mod = @import("environment.zig");
const debugPrint = env_mod.debugPrint;
const optimizations = @import("optimizations.zig");
const GeneratorObject = @import("./types/runtime.zig").GeneratorObject;
const throwError = @import("./builtins/error.zig").throwError;
const coercion = @import("coercion.zig");

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
                            else => "[object Object]",
                        };
                    } else prop.key;
                    try obj.properties.put(key, val);
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
                if (array_val.js_object.properties.get(key)) |v| {
                    return v;
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
            try object_val.js_object.properties.put(p.key, val);
            if (env.globalObject()) |g| {
                if (g == object_val.js_object) env.setGlobalProperty(p.key, val);
            }
            return val;
        },
        .Identifier => |i| {
            if (env.getFunction(i.name)) |funcNode| {
                return .{ .function = @ptrCast(funcNode) };
            } else if (env.get(i.name)) |value| {
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
                    if (obj_val != .js_object) return error.InvalidAssignment;
                    const val = try evaluate(b.right, env);
                    try obj_val.js_object.properties.put(b.left.MemberAccess.property, val);
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
                        try obj_val.js_object.properties.put(key, val);
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
                            if (obj.properties.get("@@iterator")) |iterator_fn| {
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
                        const next_val = try evaluateGeneratorNext(delegate, env);
                        if (next_val != .js_object) break;
                        const done_val = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                        const is_done = switch (done_val) {
                            .boolean => |b| b,
                            else => true,
                        };
                        const val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
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
                        const next_val = try callFunctionValue(next_fn, &.{}, env, .{ .js_object = delegate });
                        if (next_val != .js_object) {
                            env.yield_star_js_iterator = null;
                            return .{ .void = {} };
                        }
                        const done_val = next_val.js_object.properties.get("done") orelse @as(ast.Value, .{ .boolean = true });
                        const is_done = switch (done_val) {
                            .boolean => |b| b,
                            else => true,
                        };
                        const val = next_val.js_object.properties.get("value") orelse @as(ast.Value, .{ .void = {} });
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
                const val: ast.Value = if (y.value) |v| try evaluate(v, env) else .{ .void = {} };
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
            for (b.statements) |stmt| {
                if (stmt.* == .LetDeclaration or stmt.* == .ConstantDeclaration) {
                    has_block_scope = true;
                    break;
                }
            }

            if (!has_block_scope) {
                var result: ast.Value = .{ .float = 0.0 };
                for (b.statements) |stmt| {
                    if (stmt.* == .ReturnStatement) {
                        const ret_stmt = stmt.ReturnStatement;
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

            var result: ast.Value = .{ .float = 0.0 };
            for (b.statements) |stmt| {
                if (stmt.* == .ReturnStatement) {
                    const ret_stmt = stmt.ReturnStatement;
                    if (ret_stmt.value) |val| {
                        return try evaluate(val, &block_env);
                    } else {
                        return .{ .void = {} };
                    }
                }

                result = try evaluate(stmt, &block_env);
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
            const per_iter = is_let_init and ast.containsClosure(f.body);
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
                    // Track which for-loop node yielded so init is skipped on re-entry
                    env.for_yield_node = @ptrCast(node);
                    // If yield came from an active yield*, don't advance the loop variable.
                    // yield* spans multiple generator.next() calls — the loop should not
                    // advance until yield* completes and the body finishes normally.
                    env.for_yield_iter_env = @ptrCast(eval_env);
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
                    eval_env.yield_caught_by_loop = true;
                    result = eval_env.yield_value;
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
            if (env.for_yield_node == @as(?*const anyopaque, @ptrCast(node))) {
                env.for_yield_node = null;
                env.for_yield_iter_env = null;
            }
            return result;
        },
        .ForOfLoop => |f| {
            var result: ast.Value = .{ .float = 0.0 };
            const fo_my_label = env.pending_loop_label;
            env.pending_loop_label = null;

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
                .js_object => "object",
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
        .FunctionDeclaration => |f| {
            if (f.name.len > 0) try env.setFunction(f.name, node);
            // Capture the defining scope so calls keep reading/writing the
            // same bindings after the enclosing call returns.
            const scope = try env.captureEnv();
            return .{ .closure = try ast.ClosureValue.init(env.allocator, @ptrCast(@as(*anyopaque, node)), @ptrCast(scope)) };
        },
        .FunctionCall => |f| {
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
                if (has_spread_args) {
                    var expanded = try evaluateArgs(ne.arguments, env);
                    defer expanded.deinit(env.allocator);
                    const result = builtin_fn(expanded.items, env);
                    return switch (result) {
                        .value => |val| val,
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
                    return switch (result) {
                        .value => |val| val,
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
                return switch (result) {
                    .value => |val| val,
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
            if (callee_val == .closure) {
                var expanded = try evaluateArgs(dc.arguments, env);
                defer expanded.deinit(env.allocator);
                return try callFunctionValue(callee_val, expanded.items, env, ast.Value{ .void = {} });
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
        .MemberAccess => |m| {
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
            } else if (value == .js_object) {
                if (value.js_object.properties.get(m.property)) |v| {
                    return v;
                }
                return .{ .void = {} };
            } else {
                return error.InvalidMemberAccess;
            }
        },
        .MethodCall => |m| {
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
                        if (value.js_object.properties.get(m.method)) |method_val| {
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
                return switch (result4) {
                    .value => |val| val,
                    .void => .void,
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
                if (value.js_object.properties.get(m.method)) |method_val| {
                    var js_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, m.arguments.len);
                    defer js_args.deinit(env.allocator);
                    for (m.arguments) |arg| {
                        try js_args.append(env.allocator, try evaluate(arg, env));
                    }
                    return try callFunctionValue(method_val, js_args.items, env, value);
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
                return switch (result5) {
                    .value => |val| val,
                    .void => .void,
                };
            } else if (value == .function) {
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

fn invokeFunctionNode(func_node: *ast.Node, args: []ast.Value, env: *Environment, this_val: ?ast.Value) anyerror!ast.Value {
        if (func_node.* == .GeneratorDeclaration) {
            const gen_decl = func_node.GeneratorDeclaration;
            const gen_obj = try GeneratorObject.init(env.allocator, @ptrCast(func_node), gen_decl.parameters);
            errdefer gen_obj.deinit();
            var gen_env = try Environment.init(env.allocator, env);
            errdefer gen_env.deinit();
            for (gen_decl.parameters, 0..) |param, idx| {
                try gen_env.set(param, if (idx < args.len) args[idx] else .{ .void = {} });
            }
            if (this_val) |tv| {
                try gen_env.set("this", tv);
            }
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
        if (func_node.* == .FunctionDeclaration) {
            const func = func_node.FunctionDeclaration;
            // Heap-owned so closures created in the body can adopt it; freed
            // right away unless one of them actually captured it.
            const func_env = try Environment.initHeap(env.allocator, env);
            defer if (!func_env.captured) {
                func_env.deinit();
                env.allocator.destroy(func_env);
            };
            for (func.parameters, 0..) |param, idx| {
                try func_env.set(param, if (idx < args.len) args[idx] else .{ .void = {} });
            }
            if (this_val) |tv| {
                try func_env.set("this", tv);
            }
            return try evaluate(func.body, func_env);
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
                try func_env.set(param, if (idx < args.len) args[idx] else .{ .void = {} });
            }
            return try evaluate(func.body, func_env);
        }
    return error.NotAFunction;
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
            return try invokeFunctionNode(func_node, args, scope, this_val);
        },
        .generator => |gen| {
            return .{ .generator = gen };
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

pub fn evaluateGeneratorNext(gen: *GeneratorObject, caller_env: *Environment) anyerror!ast.Value {
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
    } else {
        // First call: create and store the environment
        var new_env = try Environment.init(caller_env.allocator, caller_env);
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
            gen.done = true;
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
    done_result.properties.put("value", result) catch {};
    done_result.properties.put("done", .{ .boolean = true }) catch {};
    caller_env.objects.append(caller_env.allocator, done_result) catch { done_result.deinit(); return .{ .void = {} }; };
    return .{ .js_object = done_result };
}

pub fn evaluateGeneratorReturn(gen: *GeneratorObject, caller_env: *Environment, args: []ast.Value) anyerror!ast.Value {
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
pub fn evalFn(args: []ast.Value, env: *builtinsTypes.Environment) builtinsTypes.BuiltinResult {
    if (args.len == 0 or args[0] != .string) return .{ .value = .{ .void = {} } };

    const source = args[0].string;

    var lexer = Lexer.init(source);
    var parser = Parser.init(&lexer, env.allocator) catch return .{ .value = .{ .void = {} } };
    errdefer parser.deinit();

    const program = parser.parseProgram() catch {
        parser.deinit();
        _ = throwError(env, "SyntaxError", .{ .string = "eval parse error" });
        return .{ .void = {} };
    };

    // Note: AST nodes are owned by the parser's arena and will be freed
    // when parser.deinit() is called. Do NOT append to synthetic_asts.

    var result: ast.Value = .{ .void = {} };
    @setEvalBranchQuota(2000);
    for (program) |stmt| {
        result = evaluate(stmt, @as(*Environment, @ptrCast(env))) catch {
            parser.deinit();
            return .{ .value = .{ .void = {} } };
        };
    }

    parser.deinit();
    return .{ .value = result };
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

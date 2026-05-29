const std = @import("std");
const ast = @import("ast.zig");
const builtinsTypes = @import("./types/types.zig");
const env_mod = @import("environment.zig");
const debugPrint = env_mod.debugPrint;
const optimizations = @import("optimizations.zig");
const GeneratorObject = @import("./types/runtime.zig").GeneratorObject;

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
        .closure => right == .closure,
        .iterator => right == .iterator,
        .js_object => right == .js_object,
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

pub fn evaluate(node: *ast.Node, env: *Environment) !ast.Value {
    switch (node.*) {
        .IntegerLiteral => |i| return .{ .integer = i.value },
        .FloatLiteral => |f| return .{ .float = f.value },
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
                                try array_obj.elements.append(env.allocator, item);
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
                    try obj.properties.put(prop.key, val);
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
                .integer => |i| @intCast(i),
                .float => |f| @intFromFloat(f),
                else => return error.InvalidIndex,
            };
            if (array_val.array.get(index)) |value| {
                return value;
            } else {
                return error.IndexOutOfBounds;
            }
        },
        .PropertySet => |p| {
            const object_val = try evaluate(p.object, env);
            if (object_val != .js_object) {
                return error.InvalidAssignmentTarget;
            }
            const val = try evaluate(p.value, env);
            try object_val.js_object.properties.put(p.key, val);
            return val;
        },
        .Identifier => |i| {
            if (env.getFunction(i.name)) |_| {
                return .{ .string = i.name };
            } else if (env.get(i.name)) |value| {
                return value;
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
                    return val;
                }
                if (b.left.* == .ArrayIndex) {
                    const ai = b.left.ArrayIndex;
                    const obj_val = try evaluate(ai.array, env);
                    if (obj_val != .js_object) return error.InvalidAssignment;
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
                        else => return error.InvalidIndex,
                    };
                    const val = try evaluate(b.right, env);
                    try obj_val.js_object.properties.put(key, val);
                    return val;
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
                b.operator == .ModuloAssign)
            {
                if (b.left.* != .Identifier) {
                    return error.InvalidAssignment;
                }
                const name = b.left.Identifier.name;
                const current_val = env.get(name) orelse return error.UndefinedVariable;
                const right_val = try evaluate(b.right, env);
                const result = switch (b.operator) {
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
                    else => unreachable,
                };
                try env.setInScope(name, result);
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
                    .Equal, .StrictEqual => valuesEqual(left, right),
                    .NotEqual, .StrictNotEqual => !valuesEqual(left, right),
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
                    .string => |sv| sv.len > 0,
                    .void => false,
                    else => true,
                };

                if (b.operator == .And) {
                    if (!left_truthy) return .{ .boolean = false };
                    const right = try evaluate(b.right, env);
                    const right_truthy = switch (right) {
                        .boolean => |bv| bv,
                        .integer => |iv| iv != 0,
                        .float => |fv| fv != 0.0,
                        .string => |sv| sv.len > 0,
                        .void => false,
                        else => true,
                    };
                    return .{ .boolean = right_truthy };
                } else {
                    if (left_truthy) return .{ .boolean = true };
                    const right = try evaluate(b.right, env);
                    const right_truthy = switch (right) {
                        .boolean => |bv| bv,
                        .integer => |iv| iv != 0,
                        .float => |fv| fv != 0.0,
                        .string => |sv| sv.len > 0,
                        .void => false,
                        else => true,
                    };
                    return .{ .boolean = right_truthy };
                }
            }

            const left = try evaluate(b.left, env);
            const right = try evaluate(b.right, env);

            if (b.operator == .Plus and (left == .string or right == .string)) {
                var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch return error.OutOfMemory;
                defer buf.deinit(env.allocator);
                switch (left) {
                    .string => |s| buf.appendSlice(env.allocator, s) catch return error.OutOfMemory,
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
                else => return error.UnsupportedOperator,
            };
        },
        .Assignment => |a| {
            const value = try evaluate(a.value, env);
            try env.setInScope(a.name, value);
            return value;
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
            if (c.value.* == .FunctionDeclaration or c.value.* == .ArrowFunction or c.value.* == .GeneratorDeclaration) {
                try env.setFunction(c.name, c.value);
                try env.setConstant(c.name, .{ .float = 0.0 });
                return .{ .float = 0.0 };
            } else {
                const value = try evaluate(c.value, env);
                try env.setConstant(c.name, value);
                return value;
            }
        },
        .VariableDeclaration => |v| {
            if (v.value.* == .FunctionDeclaration or v.value.* == .ArrowFunction or v.value.* == .GeneratorDeclaration) {
                try env.setFunction(v.name, v.value);
                try env.setVar(v.name, .{ .float = 0.0 });
                return .{ .float = 0.0 };
            } else {
                const value = try evaluate(v.value, env);
                try env.setVar(v.name, value);
                return value;
            }
        },
        .LetDeclaration => |v| {
            if (v.value.* == .FunctionDeclaration or v.value.* == .ArrowFunction or v.value.* == .GeneratorDeclaration) {
                try env.setFunction(v.name, v.value);
                try env.setLet(v.name, .{ .float = 0.0 });
                return .{ .float = 0.0 };
            } else {
                const value = try evaluate(v.value, env);
                try env.setLet(v.name, value);
                return value;
            }
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
                    if (env.return_hit) break;
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
                if (block_env.return_hit) break;
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
            debugPrint("[OPTIMIZATION] Trying optimizeSimpleForLoop, pre_limit={?}\n", .{pre_limit});
            if (try optimizations.optimizeSimpleForLoop(f, env, pre_limit)) |result| {
                debugPrint("[OPTIMIZATION] SUCCESS!\n", .{});
                return result;
            }
            debugPrint("[OPTIMIZATION] FAILED - falling through\n", .{});

            const is_let_init = f.init != null and f.init.?.* == .LetDeclaration;

            var loop_env_buf: Environment = undefined;
            const eval_env: *Environment = if (is_let_init) blk: {
                loop_env_buf = try Environment.initBlock(env.allocator, env);
                break :blk &loop_env_buf;
            } else env;
            defer if (is_let_init) loop_env_buf.deinit();

            var result: ast.Value = .{ .float = 0.0 };

            // Run init on first entry; skip on generator yield re-entry
            if (f.init) |init| {
                if (env.for_yield_node != @as(?*const anyopaque, @ptrCast(node))) {
                    _ = try evaluate(init, eval_env);
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
                    if (eval_env.yield_star_gen == null and eval_env.yield_star_array == null) {
                        if (f.increment) |inc| {
                            _ = try evaluate(inc, eval_env);
                        }
                    }
                    eval_env.yield_caught_by_loop = true;
                    result = eval_env.yield_value;
                    eval_env.yield_hit = false; // Consume so outer loops don't also catch it
                    break;
                }
                if (f.increment) |inc| {
                    _ = try evaluate(inc, eval_env);
                }
                if (eval_env.return_hit) break;
            }

            // For-loop completed without yielding — clear for_yield_node
            if (env.for_yield_node == @as(?*const anyopaque, @ptrCast(node))) {
                env.for_yield_node = null;
            }
            return result;
        },
        .ForOfLoop => |f| {
            var result: ast.Value = .{ .float = 0.0 };

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
                        i += cp_len;
                    }
                },
                .js_object => |obj| {
                    const type_tag = obj.properties.get("@@type");
                    if (type_tag != null and type_tag.? == .string) {
                        if (std.mem.eql(u8, type_tag.?.string, "Set")) {
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
                                    }
                                }
                            }
                        } else if (std.mem.eql(u8, type_tag.?.string, "Map")) {
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
                                    }
                                }
                            }
                        }
                    }
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
        .ReturnStatement => |r| {
            env.return_hit = true;
            if (r.value) |val| {
                const v = try evaluate(val, env);
                return v;
            } else {
                return .{ .void = {} };
            }
        },
        .GeneratorDeclaration => |g| {
            try env.setFunction(g.name, node);
            return .{ .function = @ptrCast(node) };
        },
        .FunctionDeclaration => |f| {
            try env.setFunction(f.name, node);
            return .{ .function = @ptrCast(node) };
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
            return .{ .function = @ptrCast(node) };
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
        .DirectCall => |dc| {
            const callee_val = try evaluate(dc.callee, env);
            if (callee_val == .generator) {
                // Evaluate args for side effects, then return the generator
                for (dc.arguments) |arg| {
                    _ = try evaluate(arg, env);
                }
                return callee_val;
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
                    return error.UndefinedMethod;
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
                            const method_fn = arr_builtin.getMethod(m.method) orelse return error.UndefinedMethod;
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
                            const method_fn = arr_builtin.getMethod(m.method) orelse return error.UndefinedMethod;
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
                        const method_fn2 = arr_builtin2.getMethod(m.method) orelse return error.UndefinedMethod;
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
                            const method_fn = str_builtin.getMethod(m.method) orelse return error.UndefinedMethod;
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
                            const method_fn = str_builtin.getMethod(m.method) orelse return error.UndefinedMethod;
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
                        const method_fn2 = str_builtin2.getMethod(m.method) orelse return error.UndefinedMethod;
                        const result2 = method_fn2(method_args.items, env);
                        return switch (result2) {
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
                        if (value.js_object.properties.get("@@type")) |type_val| {
                            if (type_val == .string) {
                                const builtin_obj = env.getBuiltinObject(type_val.string) orelse return .{ .void = {} };
                                const method_fn = builtin_obj.getMethod(m.method) orelse return .{ .void = {} };
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
                    return error.UndefinedMethod;
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
                    const method_fn = arr_obj.getMethod(m.method) orelse return error.UndefinedMethod;
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
                    const method_fn3 = arr_obj3.getMethod(m.method) orelse return error.UndefinedMethod;
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
                const method_fn4 = arr_obj4.getMethod(m.method) orelse return error.UndefinedMethod;
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
                    return error.UndefinedMethod;
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
                    const method_fn = str_builtin.getMethod(m.method) orelse return error.UndefinedMethod;
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
                    const method_fn = str_builtin.getMethod(m.method) orelse return error.UndefinedMethod;
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
                const method_fn2 = str_builtin2.getMethod(m.method) orelse return error.UndefinedMethod;
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
                        try env.exports.put("default", .{ .float = 0.0 });
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
                        try env.exports.put(n, .{ .float = 0.0 });
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
        if (func_node.* == .FunctionDeclaration) {
            const func = func_node.FunctionDeclaration;
            var func_env = try Environment.init(env.allocator, env);
            defer func_env.deinit();
            for (func.parameters, 0..) |param, idx| {
                try func_env.set(param, if (idx < args.len) args[idx] else .{ .void = {} });
            }
            if (this_val) |tv| {
                try func_env.set("this", tv);
            }
            return try evaluate(func.body, &func_env);
        }
        if (func_node.* == .ArrowFunction) {
            const func = func_node.ArrowFunction;
            var func_env = try Environment.init(env.allocator, env);
            defer func_env.deinit();
            for (func.parameters, 0..) |param, idx| {
                try func_env.set(param, if (idx < args.len) args[idx] else .{ .void = {} });
            }
            return try evaluate(func.body, &func_env);
        }
    return error.NotAFunction;
}

fn callFunctionValue(val: ast.Value, args: []ast.Value, env: *Environment, this_val: ?ast.Value) anyerror!ast.Value {
    switch (val) {
        .function => |fn_ptr| {
            const func_node: *ast.Node = @alignCast(@ptrCast(fn_ptr));
            return try invokeFunctionNode(func_node, args, env, this_val);
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

// --- Function tests ---

test "evaluate function declaration and call" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result_struct = try parseProgramNoFree("fn add(a, b) { return a + b }", &env_);
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

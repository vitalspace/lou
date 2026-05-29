const std = @import("std");
const ast = @import("ast.zig");
const builtinsTypes = @import("./types/types.zig");
const Env = @import("environment.zig");
const Environment = Env.Environment;
const debugPrint = Env.debugPrint;

fn getFloatValue(node: *ast.Node) ?f64 {
    return switch (node.*) {
        .FloatLiteral => |v| v.value,
        .IntegerLiteral => |v| @floatFromInt(v.value),
        else => null,
    };
}

pub fn optimizeArrayPushLoop(w: @TypeOf(@as(ast.Node, undefined).WhileLoop), env: *Environment) !?ast.Value {
    if (w.condition.* != .BinaryExpression) return null;
    const cond = w.condition.BinaryExpression;
    if (cond.operator != .LessThan) return null;
    if (cond.left.* != .Identifier) return null;
    if (cond.right.* != .FloatLiteral) return null;

    const loop_var = cond.left.Identifier.name;
    const limit = cond.right.FloatLiteral.value;

    if (w.body.* != .BlockStatement) return null;
    const body_stmts = w.body.BlockStatement.statements;
    if (body_stmts.len != 2) return null;

    if (body_stmts[0].* != .MethodCall) return null;
    const method_call = body_stmts[0].MethodCall;

    if (method_call.object.* != .Identifier) return null;
    const array_name = method_call.object.Identifier.name;

    if (!std.mem.eql(u8, method_call.method, "push")) return null;
    if (method_call.arguments.len != 1) return null;

    if (method_call.arguments[0].* != .Identifier) return null;
    const push_arg = method_call.arguments[0].Identifier.name;
    if (!std.mem.eql(u8, push_arg, loop_var)) return null;

    var increment_value: f64 = 1.0;
    const inc_stmt = body_stmts[1];

    if (inc_stmt.* == .Assignment) {
        const assign = inc_stmt.Assignment;
        if (!std.mem.eql(u8, assign.name, loop_var)) return null;
        if (assign.value.* != .BinaryExpression) return null;

        const add_expr = assign.value.BinaryExpression;
        if (add_expr.operator != .Plus) return null;
        if (add_expr.left.* != .Identifier) return null;
        if (!std.mem.eql(u8, add_expr.left.Identifier.name, loop_var)) return null;
        increment_value = getFloatValue(add_expr.right) orelse return null;
    } else if (inc_stmt.* == .BinaryExpression) {
        const inc_expr = inc_stmt.BinaryExpression;
        if (inc_expr.operator != .Assign) return null;
        if (inc_expr.left.* != .Identifier) return null;
        if (!std.mem.eql(u8, inc_expr.left.Identifier.name, loop_var)) return null;
        if (inc_expr.right.* != .BinaryExpression) return null;

        const add_expr = inc_expr.right.BinaryExpression;
        if (add_expr.operator != .Plus) return null;
        if (add_expr.left.* != .Identifier) return null;
        if (!std.mem.eql(u8, add_expr.left.Identifier.name, loop_var)) return null;

        increment_value = getFloatValue(add_expr.right) orelse return null;
    } else {
        return null;
    }

    const initial_val = env.get(loop_var) orelse return null;
    if (initial_val != .float) return null;
    const initial_value = initial_val.float;

    const array_val = env.get(array_name) orelse return null;
    if (array_val != .array) return null;

    const iterations_i64 = @divFloor(@as(i64, @intFromFloat(limit - initial_value)), @as(i64, @intFromFloat(increment_value)));
    const iterations = @as(usize, @intCast(iterations_i64));

    const current_len = array_val.array.elements.items.len;
    const new_total_capacity = current_len + iterations;

    try array_val.array.elements.ensureTotalCapacity(array_val.array.allocator, new_total_capacity);

    var i = initial_value;
    while (i < limit) : (i += increment_value) {
        array_val.array.elements.appendAssumeCapacity(.{ .float = i });
    }

    debugPrint("[ARRAY PUSH OPTIMIZATION] ✓ Completed, pushed {d} elements\n", .{iterations});

    try env.values.put(loop_var, .{ .float = i });

    return .{ .float = 0.0 };
}

pub fn optimizeSimpleForLoop(f: @TypeOf(@as(ast.Node, undefined).ForLoop), env: *Environment, pre_limit: ?f64) !?ast.Value {
    std.debug.print("", .{});

    if (f.init == null) {
        std.debug.print("", .{});
        return null;
    }

    if (f.init.?.* != .VariableDeclaration and f.init.?.* != .LetDeclaration) {
        return null;
    }

    const init_name: []const u8 = if (f.init.?.* == .VariableDeclaration)
        f.init.?.VariableDeclaration.name
    else
        f.init.?.LetDeclaration.name;

    debugPrint("[OPTIMIZATION] init_name: {s}\n", .{init_name});

    const init_value_node: *ast.Node = if (f.init.?.* == .VariableDeclaration)
        f.init.?.VariableDeclaration.value
    else
        f.init.?.LetDeclaration.value;

    const initial_value: f64 = switch (init_value_node.*) {
        .FloatLiteral => |v| v.value,
        .IntegerLiteral => |v| @floatFromInt(v.value),
        else => {
            debugPrint("[OPTIMIZATION] FAIL: init value not number, it is: {s}\n", .{@tagName(init_value_node.*)});
            return null;
        },
    };
    debugPrint("[OPTIMIZATION] initial_value: {d}\n", .{initial_value});

    const loop_var = init_name;

    if (f.condition == null) {
        return null;
    }

    if (f.condition.?.* != .BinaryExpression) {
        return null;
    }

    const cond = f.condition.?.BinaryExpression;

    if (cond.left.* != .Identifier) {
        return null;
    }

    if (!std.mem.eql(u8, cond.left.Identifier.name, loop_var)) {
        return null;
    }

    const limit: f64 = pre_limit orelse blk: {
        if (cond.right.* != .FloatLiteral and cond.right.* != .IntegerLiteral) {
            std.debug.print("", .{});
            return null;
        }
        break :blk switch (cond.right.*) {
            .FloatLiteral => |v| v.value,
            .IntegerLiteral => |v| @floatFromInt(v.value),
            else => return null,
        };
    };

    const is_less_than = cond.operator == .LessThan;

    if (!is_less_than) {
        debugPrint("[OPTIMIZATION] FAILED: operator is not LessThan, it is: {any}\n", .{cond.operator});
        return null;
    }

    if (f.increment == null) {
        debugPrint("[OPTIMIZATION] FAILED: increment is null\n", .{});
        return null;
    }

    debugPrint("[OPTIMIZATION] Increment type: {s}\n", .{@tagName(f.increment.?.*)});

    var increment_value: f64 = undefined;

    if (f.increment.?.* == .Assignment) {
        const inc = f.increment.?.Assignment;

        if (!std.mem.eql(u8, inc.name, loop_var)) {
            return null;
        }

        if (inc.value.* != .BinaryExpression) {
            return null;
        }

        const inc_expr = inc.value.BinaryExpression;

        if (inc_expr.operator != .Plus) {
            return null;
        }

        if (inc_expr.left.* != .Identifier) {
            return null;
        }

        if (!std.mem.eql(u8, inc_expr.left.Identifier.name, loop_var)) {
            return null;
        }

        increment_value = getFloatValue(inc_expr.right) orelse return null;
    } else if (f.increment.?.* == .BinaryExpression) {
        const inc_expr = f.increment.?.BinaryExpression;

        if (inc_expr.operator != .Assign) {
            return null;
        }

        if (inc_expr.left.* != .Identifier) {
            return null;
        }

        if (!std.mem.eql(u8, inc_expr.left.Identifier.name, loop_var)) {
            return null;
        }

        if (inc_expr.right.* != .BinaryExpression) {
            return null;
        }

        const add_expr = inc_expr.right.BinaryExpression;

        if (add_expr.operator != .Plus) {
            return null;
        }

        if (add_expr.left.* != .Identifier) {
            return null;
        }

        if (!std.mem.eql(u8, add_expr.left.Identifier.name, loop_var)) {
            return null;
        }

        increment_value = getFloatValue(add_expr.right) orelse return null;
    } else {
        return null;
    }

    if (f.body.* != .BlockStatement) {
        return null;
    }

    const body_statements = f.body.BlockStatement.statements;

    if (body_statements.len == 0) {
        const iterations = @divFloor(@as(i64, @intFromFloat(limit - initial_value)), @as(i64, @intFromFloat(increment_value)));
        const final_value = initial_value + (@as(f64, @floatFromInt(iterations)) * increment_value);
        try env.values.put(loop_var, .{ .float = final_value });
        return .{ .float = 0.0 };
    }

    if (body_statements.len == 1) {
        const body_stmt = body_statements[0];
        std.debug.print("", .{});
        const iterations = @divFloor(@as(i64, @intFromFloat(limit - initial_value)), @as(i64, @intFromFloat(increment_value)));
        const n = @as(f64, @floatFromInt(iterations));

        if (body_stmt.* == .Assignment) {
            const assign = body_stmt.Assignment;
            const acc_name = assign.name;
            std.debug.print("", .{});

            if (assign.value.* == .BinaryExpression) {
                const add = assign.value.BinaryExpression;
                std.debug.print("", .{});
                if (add.operator == .Plus and
                    add.left.* == .Identifier and
                    std.mem.eql(u8, add.left.Identifier.name, acc_name))
                {
                    std.debug.print("", .{});
                    const acc_val = env.get(acc_name) orelse {
                        debugPrint("[OPTIMIZATION] acc {s} not in env\n", .{acc_name});
                        return null;
                    };
                    const acc_start = switch (acc_val) {
                        .integer => |v| @as(f64, @floatFromInt(v)),
                        .float => |v| v,
                        else => return null,
                    };

                    if (add.right.* == .Identifier and
                        std.mem.eql(u8, add.right.Identifier.name, loop_var))
                    {
                        const sum = n * (initial_value + (initial_value + (n - 1.0) * increment_value)) / 2.0;
                        try env.setInScope(acc_name, .{ .float = acc_start + sum });
                        try env.values.put(loop_var, .{ .float = initial_value + n * increment_value });
                        return .{ .float = 0.0 };
                    }

                    if (getFloatValue(add.right)) |constant| {
                        try env.setInScope(acc_name, .{ .float = acc_start + n * constant });
                        try env.values.put(loop_var, .{ .float = initial_value + n * increment_value });
                        return .{ .float = 0.0 };
                    }
                }
            }
        }

        if (body_stmt.* == .BinaryExpression) {
            const be = body_stmt.BinaryExpression;
            if (be.operator == .PlusAssign and
                be.left.* == .Identifier)
            {
                const acc_name = be.left.Identifier.name;
                const acc_val = env.get(acc_name) orelse return null;
                const acc_start = switch (acc_val) {
                    .integer => |v| @as(f64, @floatFromInt(v)),
                    .float => |v| v,
                    else => return null,
                };

                if (be.right.* == .Identifier and
                    std.mem.eql(u8, be.right.Identifier.name, loop_var))
                {
                    const sum = n * (initial_value + (initial_value + (n - 1.0) * increment_value)) / 2.0;
                    try env.setInScope(acc_name, .{ .float = acc_start + sum });
                    try env.values.put(loop_var, .{ .float = initial_value + n * increment_value });
                    return .{ .float = 0.0 };
                }

                if (getFloatValue(be.right)) |constant| {
                    try env.setInScope(acc_name, .{ .float = acc_start + n * constant });
                    try env.values.put(loop_var, .{ .float = initial_value + n * increment_value });
                    return .{ .float = 0.0 };
                }
            }
        }
    }

    return null;
}

pub fn optimizeSimpleWhileLoop(w: @TypeOf(@as(ast.Node, undefined).WhileLoop), env: *Environment) !?ast.Value {
    if (w.condition.* != .BinaryExpression) return null;
    const cond = w.condition.BinaryExpression;
    if (cond.operator != .LessThan) return null;
    if (cond.left.* != .Identifier) return null;
    if (cond.right.* != .FloatLiteral and cond.right.* != .IntegerLiteral) return null;

    const loop_var = cond.left.Identifier.name;
    const limit: f64 = switch (cond.right.*) {
        .FloatLiteral => |v| v.value,
        .IntegerLiteral => |v| @floatFromInt(v.value),
        else => unreachable,
    };

    if (w.body.* != .BlockStatement) return null;
    const body_stmts = w.body.BlockStatement.statements;

    if (body_stmts.len == 0) {
        const initial_val = env.get(loop_var) orelse return null;
        const initial_value: f64 = switch (initial_val) {
            .float => |v| v,
            .integer => |v| @floatFromInt(v),
            else => return null,
        };
        _ = initial_value;
        return .{ .float = 0.0 };
    }

    if (body_stmts.len != 1 and body_stmts.len != 2) return null;

    // Don't optimize loops that contain yield (generator context)
    for (body_stmts) |stmt| {
        if (stmt.* == .YieldExpression) return null;
    }

    var increment_value: f64 = undefined;
    var acc_stmt: ?@TypeOf(body_stmts[0]) = null;

    if (body_stmts.len == 2) {
        for (body_stmts) |stmt| {
            const is_inc = switch (stmt.*) {
                .Assignment => |a| std.mem.eql(u8, a.name, loop_var),
                .BinaryExpression => |be| (be.operator == .Assign or
                    be.operator == .PlusAssign or be.operator == .MinusAssign) and
                    be.left.* == .Identifier and
                    std.mem.eql(u8, be.left.Identifier.name, loop_var),
                else => false,
            };
            if (is_inc) {
                if (stmt.* == .Assignment) {
                    const assign = stmt.Assignment;
                    if (assign.value.* != .BinaryExpression) return null;
                    const ae = assign.value.BinaryExpression;
                    if (ae.operator != .Plus) return null;
                    if (ae.left.* != .Identifier) return null;
                    if (!std.mem.eql(u8, ae.left.Identifier.name, loop_var)) return null;
                    increment_value = getFloatValue(ae.right) orelse return null;
                } else {
                    const be = stmt.BinaryExpression;
                    if (be.operator == .Assign) {
                        if (be.right.* != .BinaryExpression) return null;
                        const add = be.right.BinaryExpression;
                        if (add.operator != .Plus) return null;
                        if (add.left.* != .Identifier) return null;
                        if (!std.mem.eql(u8, add.left.Identifier.name, loop_var)) return null;
                        increment_value = getFloatValue(add.right) orelse return null;
                    } else if (be.operator == .PlusAssign) {
                        increment_value = getFloatValue(be.right) orelse return null;
                    } else if (be.operator == .MinusAssign) {
                        increment_value = getFloatValue(be.right) orelse return null;
                        increment_value = -increment_value;
                    } else {
                        return null;
                    }
                }
            } else {
                acc_stmt = stmt;
            }
        }
    } else {
        if (body_stmts[0].* == .Assignment) {
            const assign = body_stmts[0].Assignment;
            if (!std.mem.eql(u8, assign.name, loop_var)) return null;
            if (assign.value.* != .BinaryExpression) return null;
            const ae = assign.value.BinaryExpression;
            if (ae.operator != .Plus) return null;
            if (ae.left.* != .Identifier) return null;
            if (!std.mem.eql(u8, ae.left.Identifier.name, loop_var)) return null;
            increment_value = getFloatValue(ae.right) orelse return null;
        } else if (body_stmts[0].* == .BinaryExpression) {
            const be = body_stmts[0].BinaryExpression;
            if (be.operator != .Assign) return null;
            if (be.left.* != .Identifier) return null;
            if (!std.mem.eql(u8, be.left.Identifier.name, loop_var)) return null;
            if (be.right.* != .BinaryExpression) return null;
            const add = be.right.BinaryExpression;
            if (add.operator != .Plus) return null;
            if (add.left.* != .Identifier) return null;
            if (!std.mem.eql(u8, add.left.Identifier.name, loop_var)) return null;
            increment_value = getFloatValue(add.right) orelse return null;
        } else {
            return null;
        }
    }

    const initial_val = env.get(loop_var) orelse return null;
    const initial_value: f64 = switch (initial_val) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        else => return null,
    };

    const iterations = @divFloor(@as(i64, @intFromFloat(limit - initial_value)), @as(i64, @intFromFloat(increment_value)));
    const final_value = initial_value + (@as(f64, @floatFromInt(iterations)) * increment_value);
    const n = @as(f64, @floatFromInt(iterations));

    try env.values.put(loop_var, .{ .float = final_value });

    if (acc_stmt) |stmt| {
        if (stmt.* == .Assignment) {
            const assign = stmt.Assignment;
            if (assign.value.* == .BinaryExpression) {
                const add = assign.value.BinaryExpression;
                if (add.operator == .Plus and
                    add.left.* == .Identifier and
                    std.mem.eql(u8, add.left.Identifier.name, assign.name))
                {
                    const acc_val = env.get(assign.name) orelse return .{ .float = 0.0 };
                    const acc_start = switch (acc_val) {
                        .integer => |v| @as(f64, @floatFromInt(v)),
                        .float => |v| v,
                        else => return .{ .float = 0.0 },
                    };
                    if (add.right.* == .Identifier and std.mem.eql(u8, add.right.Identifier.name, loop_var)) {
                        const sum = n * (initial_value + (initial_value + (n - 1.0) * increment_value)) / 2.0;
                        try env.values.put(assign.name, .{ .float = acc_start + sum });
                    } else if (getFloatValue(add.right)) |constant| {
                        try env.values.put(assign.name, .{ .float = acc_start + n * constant });
                    }
                }
            }
        } else if (stmt.* == .BinaryExpression) {
            const be = stmt.BinaryExpression;
            if (be.operator == .PlusAssign and be.left.* == .Identifier) {
                const acc_name = be.left.Identifier.name;
                const acc_val = env.get(acc_name) orelse return .{ .float = 0.0 };
                const acc_start = switch (acc_val) {
                    .integer => |v| @as(f64, @floatFromInt(v)),
                    .float => |v| v,
                    else => return .{ .float = 0.0 },
                };
                if (be.right.* == .Identifier and std.mem.eql(u8, be.right.Identifier.name, loop_var)) {
                    const sum = n * (initial_value + (initial_value + (n - 1.0) * increment_value)) / 2.0;
                    try env.values.put(acc_name, .{ .float = acc_start + sum });
                } else if (getFloatValue(be.right)) |constant| {
                    try env.values.put(acc_name, .{ .float = acc_start + n * constant });
                }
            }
        }
    }

    return .{ .float = 0.0 };
}

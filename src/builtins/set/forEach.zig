const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const callbackThrow = @import("../callbacks.zig");
const Environment = @import("../../evaluator.zig").Environment;
const getSet = @import("set_utils.zig").getSet;
const getValues = @import("set_utils.zig").getValues;
const evaluate = @import("../../evaluator.zig").evaluate;

pub fn SetForEach(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const set_val = getSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(set_val) orelse return .{ .value = .{ .void = {} } };
    const callback = args[1];
    const func_node: *Ast.Node = switch (callback) {
        .function => |f| @as(*Ast.Node, @ptrCast(@alignCast(f))),
        .closure => |cl| @as(*Ast.Node, @ptrCast(@alignCast(cl.func_node))),
        .string => |name| env.getFunction(name) orelse return .{ .value = .{ .void = {} } },
        else => return .{ .value = .{ .void = {} } },
    };
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
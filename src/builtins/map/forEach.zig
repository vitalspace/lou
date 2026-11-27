const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;
const map_utils = @import("map_utils.zig");
const callbackThrow = @import("../callbacks.zig");

pub fn MapForEach(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const map_val = map_utils.getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = map_utils.getEntries(map_val) orelse return .{ .value = .{ .void = {} } };
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
            if (callbackThrow.propagateThrow(&func_env, env)) return .{ .value = .{ .void = {} } };
        }
        i += 1;
    }

    return .{ .value = .{ .void = {} } };
}

const evaluate = @import("../../evaluator.zig").evaluate;

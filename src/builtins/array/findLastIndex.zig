const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const callbackThrow = @import("../callbacks.zig");
const Environment = @import("../../evaluator.zig").Environment;
const evaluate = @import("../../evaluator.zig").evaluate;

fn getFuncNode(arg: Types.Value, env: *Types.Environment) ?*Ast.Node {
    return switch (arg) {
        .string => |s| env.getFunction(s),
        .function => |f| @as(*Ast.Node, @ptrCast(@alignCast(f))),
        .closure => |cl| @as(*Ast.Node, @ptrCast(@alignCast(cl.func_node))),
        else => null,
    };
}

pub fn FindLastIndex(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .integer = -1 } };
    if (args[0] != .array) return .{ .value = .{ .integer = -1 } };

    const source = args[0].array;

    const func_node = getFuncNode(args[1], env) orelse {
        return .{ .value = .{ .integer = -1 } };
    };

    const func_params: []const []const u8 = switch (func_node.*) {
        .FunctionDeclaration => |f| f.parameters,
        .ArrowFunction => |f| f.parameters,
        else => return .{ .value = .{ .integer = -1 } },
    };
    const func_body: *Ast.Node = switch (func_node.*) {
        .FunctionDeclaration => |f| f.body,
        .ArrowFunction => |f| f.body,
        else => return .{ .value = .{ .integer = -1 } },
    };

    var func_env = Environment.initCallable(env.allocator, env, args[1]) catch {
        return .{ .value = .{ .integer = -1 } };
    };
    defer func_env.deinit();

    const this_arg: Types.Value = if (args.len >= 3) args[2] else .{ .void = {} };

    var i: usize = source.elements.items.len;
    while (i > 0) {
        i -= 1;
        const element = source.elements.items[i];
        const cb_element: Types.Value = if (element == .hole) Types.Value{ .void = {} } else element;
        func_env.return_hit = false;
        if (func_params.len > 0) func_env.setVar(func_params[0], cb_element) catch {};
        if (func_params.len > 1) func_env.setVar(func_params[1], .{ .integer = @intCast(i) }) catch {};
        if (func_params.len > 2) func_env.setVar(func_params[2], args[0]) catch {};
        func_env.set("this", this_arg) catch {};

        const result = evaluate(func_body, &func_env) catch {
            return .{ .value = .{ .integer = -1 } };
        };
        if (callbackThrow.propagateThrow(&func_env, env)) return .{ .value = .{ .void = {} } };

        if (truthy(result)) return .{ .value = .{ .integer = @intCast(i) } };
    }

    return .{ .value = .{ .integer = -1 } };
}

fn truthy(v: Types.Value) bool {
    return switch (v) {
        .boolean => |b| b,
        .float => |f| f != 0.0,
        .integer => |i| i != 0,
        .big_int => |b| !b.eqlZero(),
        .string => |s| s.len > 0,
        .void, .null => false,
        else => true,
    };
}

fn createTestFunc(allocator: std.mem.Allocator, param_name: []const u8, limit: i64) !*Ast.Node {
    const body = try allocator.create(Ast.Node);
    body.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .GreaterThan,
        .right = try allocator.create(Ast.Node),
    } };
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = param_name } };
    body.BinaryExpression.right.* = .{ .IntegerLiteral = .{ .value = limit } };

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{param_name}),
        .body = body,
    } };
    return func_node;
}

fn destroyTestFunc(allocator: std.mem.Allocator, func_node: *Ast.Node) void {
    const params = func_node.ArrowFunction.parameters;
    allocator.free(params);
    const body = func_node.ArrowFunction.body;
    allocator.destroy(body.BinaryExpression.left);
    allocator.destroy(body.BinaryExpression.right);
    allocator.destroy(body);
    allocator.destroy(func_node);
}

const testing = std.testing;

test "findLastIndex returns index of last matching element" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 5 });
    try array.elements.append(allocator, .{ .integer = 12 });
    try array.elements.append(allocator, .{ .integer = 50 });
    try array.elements.append(allocator, .{ .integer = 130 });
    try array.elements.append(allocator, .{ .integer = 44 });

    const func_node = try createTestFunc(allocator, "x", 45);
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("isBig", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "isBig" } };
    const result = FindLastIndex(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 3), result.value.integer);
}

test "findLastIndex with inline function" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 5 });
    try array.elements.append(allocator, .{ .integer = 12 });
    try array.elements.append(allocator, .{ .integer = 8 });
    try array.elements.append(allocator, .{ .integer = 130 });
    try array.elements.append(allocator, .{ .integer = 44 });

    const func_node = try createTestFunc(allocator, "x", 10);
    defer destroyTestFunc(allocator, func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .function = @ptrCast(func_node) } };
    const result = FindLastIndex(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 4), result.value.integer);
}

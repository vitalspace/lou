const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;
const evaluate = @import("../../evaluator.zig").evaluate;

fn getFuncNode(arg: Types.Value, env: *Types.Environment) ?*Ast.Node {
    return switch (arg) {
        .string => |s| env.getFunction(s),
        .function => |f| @as(*Ast.Node, @ptrCast(@alignCast(f))),
        else => null,
    };
}

pub fn FindLast(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;

    const func_node = getFuncNode(args[1], env) orelse {
        return .{ .value = .{ .void = {} } };
    };

    const func_params: []const []const u8 = switch (func_node.*) {
        .FunctionDeclaration => |f| f.parameters,
        .ArrowFunction => |f| f.parameters,
        else => return .{ .value = .{ .void = {} } },
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
            return .{ .value = .{ .void = {} } };
        };

        if (truthy(result)) return .{ .value = element };
    }

    return .{ .value = .{ .void = {} } };
}

fn truthy(v: Types.Value) bool {
    return switch (v) {
        .boolean => |b| b,
        .float => |f| f != 0.0,
        .integer => |i| i != 0,
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

test "findLast returns last matching element" {
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
    const result = FindLast(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 130), result.value.integer);
}

test "findLast returns undefined when none match" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });

    const func_node = try createTestFunc(allocator, "x", 100);
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("isBig", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "isBig" } };
    const result = FindLast(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "findLast returns undefined for empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "anything" } };
    const result = FindLast(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "findLast no args returns undefined" {
    const result = FindLast(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "findLast non-array returns undefined" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "fn" } };
    const result = FindLast(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "findLast passes index to callback" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 10 });
    try array.elements.append(allocator, .{ .integer = 20 });
    try array.elements.append(allocator, .{ .integer = 30 });

    const body = try allocator.create(Ast.Node);
    body.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .GreaterThan,
        .right = try allocator.create(Ast.Node),
    } };
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = "i" } };
    body.BinaryExpression.right.* = .{ .IntegerLiteral = .{ .value = 0 } };

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{ "x", "i" }),
        .body = body,
    } };
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("indexGt0", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "indexGt0" } };
    const result = FindLast(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 30), result.value.integer);
}

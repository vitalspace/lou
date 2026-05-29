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

pub fn FindIndex(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
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

    var func_env = Environment.init(env.allocator, env) catch {
        return .{ .value = .{ .integer = -1 } };
    };
    defer func_env.deinit();

    for (source.elements.items, 0..) |element, i| {
        const cb_element: Types.Value = if (element == .hole) Types.Value{ .void = {} } else element;
        func_env.return_hit = false;
        if (func_params.len > 0) func_env.setVar(func_params[0], cb_element) catch {};
        if (func_params.len > 1) func_env.setVar(func_params[1], .{ .integer = @intCast(i) }) catch {};
        if (func_params.len > 2) func_env.setVar(func_params[2], args[0]) catch {};

        const result = evaluate(func_body, &func_env) catch {
            return .{ .value = .{ .integer = -1 } };
        };

        if (truthy(result)) return .{ .value = .{ .integer = @intCast(i) } };
    }

    return .{ .value = .{ .integer = -1 } };
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

test "findIndex returns index of first matching element" {
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
    try env.setFunction("isBig", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "isBig" } };
    const result = FindIndex(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 1), result.value.integer);
}

test "findIndex returns -1 when none match" {
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
    const result = FindIndex(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "findIndex returns -1 for empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "anything" } };
    const result = FindIndex(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "findIndex no args returns -1" {
    const result = FindIndex(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "findIndex non-array returns -1" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "fn" } };
    const result = FindIndex(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, -1), result.value.integer);
}

test "findIndex passes index to callback" {
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
        .operator = .Equal,
        .right = try allocator.create(Ast.Node),
    } };
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = "i" } };
    body.BinaryExpression.right.* = .{ .IntegerLiteral = .{ .value = 2 } };

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{ "x", "i" }),
        .body = body,
    } };
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("indexEq2", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "indexEq2" } };
    const result = FindIndex(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 2), result.value.integer);
}

test "findIndex with inline function" {
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
    const result = FindIndex(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 1), result.value.integer);
}

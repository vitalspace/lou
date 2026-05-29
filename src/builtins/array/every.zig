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

pub fn Every(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .boolean = true } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;

    if (source.elements.items.len == 0) return .{ .value = .{ .boolean = true } };

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

    for (source.elements.items, 0..) |element, i| {
        if (element == .hole) continue;
        func_env.return_hit = false;
        if (func_params.len > 0) func_env.setVar(func_params[0], element) catch {};
        if (func_params.len > 1) func_env.setVar(func_params[1], .{ .integer = @intCast(i) }) catch {};
        if (func_params.len > 2) func_env.setVar(func_params[2], args[0]) catch {};

        const result = evaluate(func_body, &func_env) catch {
            return .{ .value = .{ .void = {} } };
        };

        if (!truthy(result)) return .{ .value = .{ .boolean = false } };
    }

    return .{ .value = .{ .boolean = true } };
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
        .operator = .LessThan,
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

test "every returns true for all passing" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 10 });
    try array.elements.append(allocator, .{ .integer = 20 });
    try array.elements.append(allocator, .{ .integer = 30 });

    const func_node = try createTestFunc(allocator, "x", 100);
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("isSmall", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "isSmall" } };
    const result = Every(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(result.value.boolean);
}

test "every returns false when one fails" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 10 });
    try array.elements.append(allocator, .{ .integer = 50 });
    try array.elements.append(allocator, .{ .integer = 30 });

    const func_node = try createTestFunc(allocator, "x", 40);
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("isBelow", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "isBelow" } };
    const result = Every(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(!result.value.boolean);
}

test "every returns true for empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "anything" } };
    const result = Every(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(result.value.boolean);
}

test "every no args returns true" {
    const result = Every(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(result.value.boolean);
}

test "every non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "fn" } };
    const result = Every(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

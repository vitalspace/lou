const std = @import("std");
const testing = std.testing;
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
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

pub fn Filter(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
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

    var result = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    result.elements.ensureTotalCapacity(env.allocator, source.elements.items.len) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, result) catch {
        return .{ .value = .{ .void = {} } };
    };

    var func_env = Environment.initCallable(env.allocator, env, args[1]) catch {
        return .{ .value = .{ .void = {} } };
    };
    defer func_env.deinit();

    const this_arg: Types.Value = if (args.len >= 3) args[2] else .{ .void = {} };

    for (source.elements.items, 0..) |element, i| {
        if (element == .hole) continue;
        func_env.return_hit = false;
        if (func_params.len > 0) func_env.setVar(func_params[0], element) catch {};
        if (func_params.len > 1) func_env.setVar(func_params[1], .{ .integer = @intCast(i) }) catch {};
        if (func_params.len > 2) func_env.setVar(func_params[2], args[0]) catch {};
        func_env.set("this", this_arg) catch {};

        const ret = evaluate(func_body, &func_env) catch {
            return .{ .value = .{ .void = {} } };
        };

        if (truthy(ret)) {
            result.elements.appendAssumeCapacity(element);
        }
    }

    return .{ .value = .{ .array = result } };
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

fn createTestFilterFunc(allocator: std.mem.Allocator, param_name: []const u8, limit: i64) !*Ast.Node {
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

test "filter returns elements that pass test" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 10 });
    try array.elements.append(allocator, .{ .integer = 20 });
    try array.elements.append(allocator, .{ .integer = 30 });
    try array.elements.append(allocator, .{ .integer = 5 });

    const func_node = try createTestFilterFunc(allocator, "x", 9);
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("isBig", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "isBig" } };
    const result = Filter(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const filtered = result.value.array;
    try testing.expect(filtered.elements.items.len == 3);
    try testing.expect(filtered.elements.items[0].integer == 10);
    try testing.expect(filtered.elements.items[1].integer == 20);
    try testing.expect(filtered.elements.items[2].integer == 30);
}

test "filter returns empty when none pass" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });

    const func_node = try createTestFilterFunc(allocator, "x", 100);
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("isBig", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "isBig" } };
    const result = Filter(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items.len == 0);
}

test "filter no args returns void" {
    const result = Filter(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "filter non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "fn" } };
    const result = Filter(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "filter with index arg passes index" {
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
    const result = Filter(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items.len == 2);
    try testing.expect(result.value.array.elements.items[0].integer == 20);
    try testing.expect(result.value.array.elements.items[1].integer == 30);
}

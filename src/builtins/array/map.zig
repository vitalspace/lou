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

pub fn Map(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;

    // Empty array returns empty array immediately
    if (source.elements.items.len == 0) {
        const result = Ast.ArrayObject.init(env.allocator) catch {
            return .{ .value = .{ .void = {} } };
        };
        env.arrays.append(env.allocator, result) catch {
            return .{ .value = .{ .void = {} } };
        };
        return .{ .value = .{ .array = result } };
    }

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

    var func_env = Environment.init(env.allocator, env) catch {
        return .{ .value = .{ .void = {} } };
    };
    defer func_env.deinit();

    const this_arg: Types.Value = if (args.len >= 3) args[2] else .{ .void = {} };

    for (source.elements.items, 0..) |element, i| {
        if (element == .hole) {
            result.elements.appendAssumeCapacity(.{ .hole = {} });
            continue;
        }
        func_env.return_hit = false;
        if (func_params.len > 0) func_env.setVar(func_params[0], element) catch {};
        if (func_params.len > 1) func_env.setVar(func_params[1], .{ .integer = @intCast(i) }) catch {};
        if (func_params.len > 2) func_env.setVar(func_params[2], args[0]) catch {};
        func_env.set("this", this_arg) catch {};

        const mapped = evaluate(func_body, &func_env) catch {
            return .{ .value = .{ .void = {} } };
        };

        result.elements.appendAssumeCapacity(mapped);
    }

    return .{ .value = .{ .array = result } };
}

fn createTestMapFunc(allocator: std.mem.Allocator, param_name: []const u8) !*Ast.Node {
    const body = try allocator.create(Ast.Node);
    body.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .Multiply,
        .right = try allocator.create(Ast.Node),
    } };
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = param_name } };
    body.BinaryExpression.right.* = .{ .IntegerLiteral = .{ .value = 2 } };

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

test "map doubles each element" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    const func_node = try createTestMapFunc(allocator, "x");
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("double", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "double" } };
    const result = Map(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const mapped = result.value.array;
    try testing.expect(mapped.elements.items.len == 3);
    try testing.expectEqual(@as(i64, 2), mapped.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 4), mapped.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 6), mapped.elements.items[2].integer);
}

test "map with index" {
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
        .operator = .Plus,
        .right = try allocator.create(Ast.Node),
    } };
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = "v" } };
    body.BinaryExpression.right.* = .{ .Identifier = .{ .name = "i" } };

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{ "v", "i" }),
        .body = body,
    } };
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("addIdx", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "addIdx" } };
    const result = Map(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const mapped = result.value.array;
    try testing.expect(mapped.elements.items.len == 3);
    try testing.expectEqual(@as(i64, 10), mapped.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 21), mapped.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 32), mapped.elements.items[2].integer);
}

test "map empty array returns empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "anything" } };
    const result = Map(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expect(result.value.array.elements.items.len == 0);
}

test "map no args returns void" {
    const result = Map(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "map non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "fn" } };
    const result = Map(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

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

pub fn ReduceRight(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;

    const has_initial = args.len > 2;

    if (source.elements.items.len == 0) {
        if (has_initial) return .{ .value = args[2] };
        return .{ .value = .{ .void = {} } };
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

    var func_env = Environment.init(env.allocator, env) catch {
        return .{ .value = .{ .void = {} } };
    };
    defer func_env.deinit();

    var accumulator: Types.Value = undefined;
    var i: usize = 0;

    if (has_initial) {
        accumulator = args[2];
        i = source.elements.items.len;
    } else {
        accumulator = source.elements.items[source.elements.items.len - 1];
        i = source.elements.items.len - 1;
    }

    while (i > 0) {
        i -= 1;
        const element = source.elements.items[i];
        func_env.return_hit = false;
        if (func_params.len > 0) func_env.setVar(func_params[0], accumulator) catch {};
        if (func_params.len > 1) func_env.setVar(func_params[1], element) catch {};
        if (func_params.len > 2) func_env.setVar(func_params[2], .{ .integer = @intCast(i) }) catch {};
        if (func_params.len > 3) func_env.setVar(func_params[3], args[0]) catch {};

        accumulator = evaluate(func_body, &func_env) catch {
            return .{ .value = .{ .void = {} } };
        };
    }

    return .{ .value = accumulator };
}

fn createTestReduceFunc(allocator: std.mem.Allocator, param1: []const u8, param2: []const u8) !*Ast.Node {
    const body = try allocator.create(Ast.Node);
    body.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .Plus,
        .right = try allocator.create(Ast.Node),
    } };
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = param1 } };
    body.BinaryExpression.right.* = .{ .Identifier = .{ .name = param2 } };

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{ param1, param2 }),
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

test "reduceRight with initialValue sums elements" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });
    try array.elements.append(allocator, .{ .integer = 4 });

    const func_node = try createTestReduceFunc(allocator, "acc", "v");
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("sum", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "sum" }, .{ .integer = 0 } };
    const result = ReduceRight(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 10), result.value.integer);
}

test "reduceRight without initialValue sums elements" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    const func_node = try createTestReduceFunc(allocator, "acc", "v");
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("sum", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "sum" } };
    const result = ReduceRight(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 6), result.value.integer);
}

test "reduceRight empty array with initialValue returns initialValue" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "anything" }, .{ .integer = 42 } };
    const result = ReduceRight(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 42), result.value.integer);
}

test "reduceRight empty array without initialValue returns void" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "anything" } };
    const result = ReduceRight(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "reduceRight no args returns void" {
    const result = ReduceRight(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "reduceRight non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "fn" } };
    const result = ReduceRight(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "reduceRight single element without initialValue returns that element" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 99 });

    const func_node = try createTestReduceFunc(allocator, "a", "b");
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("f", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "f" } };
    const result = ReduceRight(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 99), result.value.integer);
}

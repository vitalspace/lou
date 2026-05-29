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
        else => null,
    };
}

pub fn FlatMap(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
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

    const result_count_estimate = source.elements.items.len * 2;
    var result = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    result.elements.ensureTotalCapacity(env.allocator, result_count_estimate) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, result) catch {
        return .{ .value = .{ .void = {} } };
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

        const ret = evaluate(func_body, &func_env) catch {
            return .{ .value = .{ .void = {} } };
        };

        switch (ret) {
            .array => |arr| {
                for (arr.elements.items) |item| {
                    result.elements.append(env.allocator, item) catch {
                        return .{ .value = .{ .void = {} } };
                    };
                }
            },
            else => {
                result.elements.append(env.allocator, ret) catch {
                    return .{ .value = .{ .void = {} } };
                };
            },
        }
    }

    return .{ .value = .{ .array = result } };
}

fn createTestFlatMapFunc(allocator: std.mem.Allocator, param_name: []const u8) !*Ast.Node {
    const elements = try allocator.alloc(*Ast.Node, 2);

    elements[0] = try allocator.create(Ast.Node);
    elements[0].* = .{ .Identifier = .{ .name = param_name } };

    elements[1] = try allocator.create(Ast.Node);
    elements[1].* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .Multiply,
        .right = try allocator.create(Ast.Node),
    } };
    elements[1].BinaryExpression.left.* = .{ .Identifier = .{ .name = param_name } };
    elements[1].BinaryExpression.right.* = .{ .IntegerLiteral = .{ .value = 2 } };

    const body = try allocator.create(Ast.Node);
    body.* = .{ .ArrayLiteral = .{ .elements = elements } };

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
    const arr_lit = &body.ArrayLiteral;
    for (arr_lit.elements) |elem| {
        switch (elem.*) {
            .BinaryExpression => |be| {
                allocator.destroy(be.left);
                allocator.destroy(be.right);
            },
            else => {},
        }
        allocator.destroy(elem);
    }
    allocator.free(arr_lit.elements);
    allocator.destroy(body);
    allocator.destroy(func_node);
}

test "flatMap flattens callback results by one level" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    const func_node = try createTestFlatMapFunc(allocator, "x");
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("dup", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "dup" } };
    const result = FlatMap(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const flat = result.value.array;
    try testing.expectEqual(@as(usize, 6), flat.elements.items.len);
    try testing.expectEqual(@as(i64, 1), flat.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 2), flat.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 2), flat.elements.items[2].integer);
    try testing.expectEqual(@as(i64, 4), flat.elements.items[3].integer);
    try testing.expectEqual(@as(i64, 3), flat.elements.items[4].integer);
    try testing.expectEqual(@as(i64, 6), flat.elements.items[5].integer);
}

test "flatMap with callback returning non-array acts like map" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });

    const body = try allocator.create(Ast.Node);
    body.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .Multiply,
        .right = try allocator.create(Ast.Node),
    } };
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = "x" } };
    body.BinaryExpression.right.* = .{ .IntegerLiteral = .{ .value = 10 } };

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{"x"}),
        .body = body,
    } };
    defer {
        allocator.free(func_node.ArrowFunction.parameters);
        allocator.destroy(body.BinaryExpression.left);
        allocator.destroy(body.BinaryExpression.right);
        allocator.destroy(body);
        allocator.destroy(func_node);
    }
    try env.setFunction("times10", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "times10" } };
    const result = FlatMap(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const flat = result.value.array;
    try testing.expectEqual(@as(usize, 2), flat.elements.items.len);
    try testing.expectEqual(@as(i64, 10), flat.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 20), flat.elements.items[1].integer);
}

test "flatMap no args returns void" {
    const result = FlatMap(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "flatMap non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "fn" } };
    const result = FlatMap(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "flatMap empty array returns empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    const func_node = try createTestFlatMapFunc(allocator, "x");
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("dup", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "dup" } };
    const result = FlatMap(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 0), result.value.array.elements.items.len);
}

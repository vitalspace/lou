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

pub fn Reduce(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
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
    var start_index: usize = 0;

    if (has_initial) {
        accumulator = args[2];
    } else {
        // Find first non-hole element
        start_index = 0;
        var found = false;
        for (source.elements.items, 0..) |elem, idx| {
            if (elem != .hole) {
                accumulator = elem;
                start_index = idx + 1;
                found = true;
                break;
            }
        }
        if (!found) return .{ .value = .{ .void = {} } };
    }

    for (source.elements.items[start_index..], start_index..) |element, i| {
        if (element == .hole) continue;
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

test "reduce with initialValue sums elements" {
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
    const result = Reduce(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 10), result.value.integer);
}

test "reduce without initialValue sums elements" {
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
    const result = Reduce(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 6), result.value.integer);
}

test "reduce empty array with initialValue returns initialValue" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "anything" }, .{ .integer = 42 } };
    const result = Reduce(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 42), result.value.integer);
}

test "reduce empty array without initialValue returns void" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "anything" } };
    const result = Reduce(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "reduce no args returns void" {
    const result = Reduce(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "reduce non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "fn" } };
    const result = Reduce(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "reduce with index parameter" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    const body = try allocator.create(Ast.Node);
    body.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .Plus,
        .right = try allocator.create(Ast.Node),
    } };
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = "acc" } };
    body.BinaryExpression.right.* = .{ .Identifier = .{ .name = "i" } };

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{ "acc", "v", "i" }),
        .body = body,
    } };
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("f", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "f" }, .{ .integer = 0 } };
    const result = Reduce(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    // acc starts 0, then acc + i for each: 0+0=0, 0+1=1, 1+2=3
    try testing.expectEqual(@as(i64, 3), result.value.integer);
}

test "reduce single element without initialValue returns that element" {
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
    const result = Reduce(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 99), result.value.integer);
}

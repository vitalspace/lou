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

pub fn ForEach(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
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

    var func_env = Environment.initBlock(env.allocator, env) catch {
        return .{ .value = .{ .void = {} } };
    };
    defer func_env.deinit();

    for (source.elements.items, 0..) |element, i| {
        if (element == .hole) continue;
        func_env.return_hit = false;
        if (func_params.len > 0) func_env.setVar(func_params[0], element) catch {};
        if (func_params.len > 1) func_env.setVar(func_params[1], .{ .integer = @intCast(i) }) catch {};
        if (func_params.len > 2) func_env.setVar(func_params[2], args[0]) catch {};

        _ = evaluate(func_body, &func_env) catch {
            return .{ .value = .{ .void = {} } };
        };
    }

    return .{ .value = .{ .void = {} } };
}

fn createTestFunc(allocator: std.mem.Allocator, param_name: []const u8) !*Ast.Node {
    const body = try allocator.create(Ast.Node);
    body.* = .{ .Identifier = .{ .name = param_name } };

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
    allocator.destroy(body);
    allocator.destroy(func_node);
}

const testing = std.testing;

test "forEach calls callback and returns void" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    const func_node = try createTestFunc(allocator, "x");
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("cb", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "cb" } };
    const result = ForEach(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "forEach empty array returns void" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "anything" } };
    const result = ForEach(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "forEach no args returns void" {
    const result = ForEach(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "forEach non-array returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .string = "fn" } };
    const result = ForEach(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "forEach with inline function" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 10 });
    try array.elements.append(allocator, .{ .integer = 20 });

    const func_node = try createTestFunc(allocator, "x");
    defer destroyTestFunc(allocator, func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .function = @ptrCast(func_node) } };
    const result = ForEach(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

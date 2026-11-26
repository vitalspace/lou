const std = @import("std");
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

fn valToString(val: Types.Value, allocator: std.mem.Allocator) ![]const u8 {
    return switch (val) {
        .integer => |i| std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| std.fmt.allocPrint(allocator, "{d}", .{f}),
        .big_int => |b| blk: {
            // Use the BigInt's digit string (without 'n' suffix) so numeric
            // sort order is preserved (1n < 10n < 100n).
            const digits = b.toString(allocator) catch break :blk try allocator.dupe(u8, "");
            // Digits is owned; copy so the caller's defer can free it
            // independently of the returned slice.
            const duped = try allocator.dupe(u8, digits);
            allocator.free(digits);
            break :blk duped;
        },
        .string => |s| try allocator.dupe(u8, s),
        .boolean => |b| try allocator.dupe(u8, if (b) "true" else "false"),
        .null => try allocator.dupe(u8, "null"),
        .void => try allocator.dupe(u8, "undefined"),
        else => try allocator.dupe(u8, ""),
    };
}

fn compareValues(a: Types.Value, b: Types.Value, allocator: std.mem.Allocator) i64 {
    const a_str = valToString(a, allocator) catch return 0;
    defer allocator.free(a_str);
    const b_str = valToString(b, allocator) catch return 0;
    defer allocator.free(b_str);

    if (std.mem.order(u8, a_str, b_str) == .lt) return -1;
    if (std.mem.order(u8, a_str, b_str) == .gt) return 1;
    return 0;
}

pub fn Sort(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const arr = args[0].array;
    const items = arr.elements.items;

    if (items.len < 2) return .{ .value = .{ .array = arr } };

    const has_compare = args.len > 1;
    const compare_node = if (has_compare) getFuncNode(args[1], env) else null;

    if (has_compare and compare_node == null) return .{ .value = .{ .void = {} } };

    var compare_env: ?Environment = null;
    if (compare_node != null) {
        compare_env = Environment.initCallable(env.allocator, env, args[1]) catch {
            return .{ .value = .{ .void = {} } };
        };
    }
    defer if (compare_env) |*ce| ce.deinit();

    // insertion sort
    for (1..items.len) |i| {
        const key = items[i];
        var j: i64 = @intCast(i);
        j -= 1;

        while (j >= 0) {
            var cmp: i64 = 0;
            if (compare_node) |cn| {
                const params: []const []const u8 = switch (cn.*) {
                    .FunctionDeclaration => |f| f.parameters,
                    .ArrowFunction => |f| f.parameters,
                    else => return .{ .value = .{ .void = {} } },
                };
                const body: *Ast.Node = switch (cn.*) {
                    .FunctionDeclaration => |f| f.body,
                    .ArrowFunction => |f| f.body,
                    else => return .{ .value = .{ .void = {} } },
                };

                if (compare_env) |*ce| {
                    ce.return_hit = false;
                    if (params.len > 0) ce.setVar(params[0], items[@as(usize, @intCast(j))]) catch {};
                    if (params.len > 1) ce.setVar(params[1], key) catch {};

                    const cmp_result = evaluate(body, ce) catch {
                        return .{ .value = .{ .void = {} } };
                    };

                    cmp = switch (cmp_result) {
                        .integer => |iv| iv,
                        .float => |fv| @intFromFloat(fv),
                        else => 0,
                    };
                }
            } else {
                cmp = compareValues(items[@as(usize, @intCast(j))], key, env.allocator);
            }

            if (cmp > 0) {
                const uj: usize = @intCast(j);
                items[uj + 1] = items[uj];
                j -= 1;
            } else {
                break;
            }
        }
        const uj: usize = @intCast(j + 1);
        items[uj] = key;
    }

    return .{ .value = .{ .array = arr } };
}

const testing = std.testing;

test "sort strings default" {
    const allocator = testing.allocator;

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "March" });
    try array.elements.append(allocator, .{ .string = "Jan" });
    try array.elements.append(allocator, .{ .string = "Nov" });

    var env = try Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = Sort(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqualSlices(u8, "Jan", array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "March", array.elements.items[1].string);
    try testing.expectEqualSlices(u8, "Nov", array.elements.items[2].string);
}

test "sort returns same array" {
    const allocator = testing.allocator;

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "a" });

    var env = try Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = Sort(&args, &env);

    try testing.expect(result.value.array == array);
}

test "sort empty array" {
    const allocator = testing.allocator;

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var env = try Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = Sort(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
}

test "sort no args returns void" {
    const result = Sort(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "sort non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = Sort(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "sort numbers as strings" {
    const allocator = testing.allocator;

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 30 });
    try array.elements.append(allocator, .{ .integer = 4 });
    try array.elements.append(allocator, .{ .integer = 21 });
    try array.elements.append(allocator, .{ .integer = 100000 });

    var env = try Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    _ = Sort(&args, &env);

    try testing.expectEqual(@as(i64, 1), array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 100000), array.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 21), array.elements.items[2].integer);
    try testing.expectEqual(@as(i64, 30), array.elements.items[3].integer);
    try testing.expectEqual(@as(i64, 4), array.elements.items[4].integer);
}

test "sort with compare fn ascending" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 30 });
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 4 });

    const body = try allocator.create(Ast.Node);
    defer allocator.destroy(body);
    body.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .Minus,
        .right = try allocator.create(Ast.Node),
    } };
    defer allocator.destroy(body.BinaryExpression.left);
    defer allocator.destroy(body.BinaryExpression.right);
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = "a" } };
    body.BinaryExpression.right.* = .{ .Identifier = .{ .name = "b" } };

    const func_node = try allocator.create(Ast.Node);
    defer allocator.destroy(func_node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{ "a", "b" }),
        .body = body,
    } };
    defer allocator.free(func_node.ArrowFunction.parameters);

    try env.setFunction("asc", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "asc" } };
    _ = Sort(&args, &env);

    try testing.expectEqual(@as(i64, 1), array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 4), array.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 30), array.elements.items[2].integer);
}

test "sort with compare fn descending" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 30 });
    try array.elements.append(allocator, .{ .integer = 4 });

    const body = try allocator.create(Ast.Node);
    defer allocator.destroy(body);
    body.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .Minus,
        .right = try allocator.create(Ast.Node),
    } };
    defer allocator.destroy(body.BinaryExpression.left);
    defer allocator.destroy(body.BinaryExpression.right);
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = "b" } };
    body.BinaryExpression.right.* = .{ .Identifier = .{ .name = "a" } };

    const func_node = try allocator.create(Ast.Node);
    defer allocator.destroy(func_node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{ "a", "b" }),
        .body = body,
    } };
    defer allocator.free(func_node.ArrowFunction.parameters);

    try env.setFunction("desc", func_node);

    var args = [_]Types.Value{ .{ .array = array }, .{ .string = "desc" } };
    _ = Sort(&args, &env);

    try testing.expectEqual(@as(i64, 30), array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 4), array.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 1), array.elements.items[2].integer);
}

test "sort single element" {
    const allocator = testing.allocator;

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "only" });

    var env = try Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    _ = Sort(&args, &env);

    try testing.expectEqual(@as(usize, 1), array.elements.items.len);
    try testing.expectEqualSlices(u8, "only", array.elements.items[0].string);
}

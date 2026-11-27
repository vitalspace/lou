const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;
const evaluate = @import("../../evaluator.zig").evaluate;
const callbackThrow = @import("../callbacks.zig");

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

pub fn ToSorted(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .array) return .{ .value = .{ .void = {} } };

    const source = args[0].array;
    const len = source.elements.items.len;

    var new_array = Ast.ArrayObject.init(source.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    errdefer new_array.deinit();

    // copy all elements
    new_array.elements.ensureTotalCapacity(source.allocator, len) catch {
        return .{ .value = .{ .void = {} } };
    };
    for (source.elements.items) |item| {
        new_array.elements.appendAssumeCapacity(item);
    }

    if (len < 2) {
        env.arrays.append(env.allocator, new_array) catch {
            new_array.deinit();
            return .{ .value = .{ .void = {} } };
        };
        return .{ .value = .{ .array = new_array } };
    }

    const has_compare = args.len > 1;
    const compare_node = if (has_compare) getFuncNode(args[1], env) else null;

    if (has_compare and compare_node == null) {
        env.arrays.append(env.allocator, new_array) catch {
            new_array.deinit();
            return .{ .value = .{ .void = {} } };
        };
        return .{ .value = .{ .array = new_array } };
    }

    var compare_env: ?Environment = null;
    if (compare_node != null) {
        compare_env = Environment.initCallable(env.allocator, env, args[1]) catch {
            return .{ .value = .{ .void = {} } };
        };
    }
    defer if (compare_env) |*ce| ce.deinit();

    const items = new_array.elements.items;

    // insertion sort on the copy
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
                    if (callbackThrow.propagateThrow(ce, env)) return .{ .value = .{ .void = {} } };

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

    env.arrays.append(env.allocator, new_array) catch {
        new_array.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .array = new_array } };
}

const testing = std.testing;

test "toSorted returns new sorted array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "March" });
    try array.elements.append(allocator, .{ .string = "Jan" });
    try array.elements.append(allocator, .{ .string = "Nov" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToSorted(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    const sorted = result.value.array;
    try testing.expectEqual(@as(usize, 3), sorted.elements.items.len);
    try testing.expectEqualSlices(u8, "Jan", sorted.elements.items[0].string);
    try testing.expectEqualSlices(u8, "March", sorted.elements.items[1].string);
    try testing.expectEqualSlices(u8, "Nov", sorted.elements.items[2].string);
}

test "toSorted does not mutate original" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "a" });

    var args = [_]Types.Value{.{ .array = array }};
    _ = ToSorted(&args, &env);

    try testing.expectEqualSlices(u8, "b", array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "a", array.elements.items[1].string);
}

test "toSorted returns different array instance" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "b" });
    try array.elements.append(allocator, .{ .string = "a" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToSorted(&args, &env);

    try testing.expect(result.value.array != array);
}

test "toSorted numbers as strings" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 30 });
    try array.elements.append(allocator, .{ .integer = 4 });
    try array.elements.append(allocator, .{ .integer = 21 });
    try array.elements.append(allocator, .{ .integer = 100000 });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToSorted(&args, &env);

    const sorted = result.value.array;
    try testing.expectEqual(@as(i64, 1), sorted.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 100000), sorted.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 21), sorted.elements.items[2].integer);
    try testing.expectEqual(@as(i64, 30), sorted.elements.items[3].integer);
    try testing.expectEqual(@as(i64, 4), sorted.elements.items[4].integer);
}

test "toSorted with compare fn ascending" {
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
    const result = ToSorted(&args, &env);

    const sorted = result.value.array;
    try testing.expectEqual(@as(i64, 1), sorted.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 4), sorted.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 30), sorted.elements.items[2].integer);
}

test "toSorted with compare fn descending" {
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
    const result = ToSorted(&args, &env);

    const sorted = result.value.array;
    try testing.expectEqual(@as(i64, 30), sorted.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 4), sorted.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 1), sorted.elements.items[2].integer);
}

test "toSorted empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToSorted(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 0), result.value.array.elements.items.len);
}

test "toSorted single element" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .string = "only" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = ToSorted(&args, &env);

    try testing.expectEqual(@as(usize, 1), result.value.array.elements.items.len);
    try testing.expectEqualSlices(u8, "only", result.value.array.elements.items[0].string);
}

test "toSorted no args returns void" {
    const result = ToSorted(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "toSorted non-array returns void" {
    var args = [_]Types.Value{.{ .integer = 42 }};
    const result = ToSorted(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

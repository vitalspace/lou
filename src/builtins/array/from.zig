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

/// Consume an iterator protocol js_object: calls next() repeatedly until done=true
fn consumeIteratorProtocol(iter_obj: *Types.ObjectValue, new_array: *Ast.ArrayObject, env: *Types.Environment) !void {
    while (true) {
        // Call next() on the iterator
        const next_fn_name = "next";
        const next_method_val = iter_obj.properties.get(next_fn_name) orelse break;
        if (next_method_val != .function) break;
        const func_node: *Ast.Node = @ptrCast(@alignCast(next_method_val.function));
        const func_body: *Ast.Node = switch (func_node.*) {
            .FunctionDeclaration => |f| f.body,
            .ArrowFunction => |f| f.body,
            else => break,
        };
        var func_env = Environment.init(env.allocator, env) catch break;
        defer func_env.deinit();
        func_env.setVar("this", .{ .js_object = iter_obj }) catch {};
        const result = evaluate(func_body, &func_env) catch break;
        if (result != .js_object) break;
        const r_obj = result.js_object;
        const done_opt = r_obj.properties.get("done");
        const done = if (done_opt) |d| d else Types.Value{ .boolean = false };
        if (done == .boolean and done.boolean) break;
        const value_opt = r_obj.properties.get("value");
        const value = if (value_opt) |v| v else Types.Value{ .void = {} };
        try new_array.elements.append(env.allocator, value);
    }
}

pub fn From(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) {
        const empty = Ast.ArrayObject.init(env.allocator) catch {
            return .{ .value = .{ .void = {} } };
        };
        env.arrays.append(env.allocator, empty) catch {
            empty.deinit();
            return .{ .value = .{ .void = {} } };
        };
        return .{ .value = .{ .array = empty } };
    }

    const source = args[0];

    var new_array = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    errdefer new_array.deinit();

    switch (source) {
        .array => |arr| {
            for (arr.elements.items) |elem| {
                new_array.elements.append(env.allocator, elem) catch {
                    return .{ .value = .{ .void = {} } };
                };
            }
        },
        .string => |s| {
            var i: usize = 0;
            while (i < s.len) {
                const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
                const slice = s[i .. i + byte_len];
                const owned = env.allocator.dupe(u8, slice) catch {
                    return .{ .value = .{ .void = {} } };
                };
                env.owned_strings.append(env.allocator, owned) catch {};
                new_array.elements.append(env.allocator, .{ .string = owned }) catch {
                    return .{ .value = .{ .void = {} } };
                };
                i += byte_len;
            }
        },
        .iterator => |iter| {
            while (true) {
                const result = iter.next(env.allocator, &env.arrays, &env.objects);
                if (result != .js_object) break;
                const obj = result.js_object;
                const done_opt = obj.properties.get("done");
                const done = if (done_opt) |d| d else Types.Value{ .boolean = false };
                if (done == .boolean and done.boolean) break;
                const value_opt = obj.properties.get("value");
                const value = if (value_opt) |v| v else Types.Value{ .void = {} };
                new_array.elements.append(env.allocator, value) catch {
                    return .{ .value = .{ .void = {} } };
                };
            }
        },
        .js_object => |obj| {
            const type_tag = obj.properties.get("@@type");
            var iter_consumed = false;

            // Handle Set directly
            if (type_tag != null and type_tag.? == .string and std.mem.eql(u8, type_tag.?.string, "Set")) {
                if (obj.properties.get("values")) |vals| {
                    if (vals == .array) {
                        for (vals.array.elements.items) |elem| {
                            new_array.elements.append(env.allocator, elem) catch {
                                return .{ .value = .{ .void = {} } };
                            };
                        }
                    }
                }
                iter_consumed = true;
            }

            // Handle Map directly
            if (!iter_consumed and type_tag != null and type_tag.? == .string and std.mem.eql(u8, type_tag.?.string, "Map")) {
                if (obj.properties.get("entries")) |ents| {
                    if (ents == .array) {
                        for (ents.array.elements.items) |pair| {
                            if (pair == .array) {
                                new_array.elements.append(env.allocator, pair) catch {
                                    return .{ .value = .{ .void = {} } };
                                };
                            }
                        }
                    }
                }
                iter_consumed = true;
            }

            // Try @@iterator
            if (!iter_consumed) {
                const iterator_key = "@@iterator";
                if (obj.properties.get(iterator_key)) |iter_val| {
                    if (iter_val == .string) {
                        const func_node = env.getFunction(iter_val.string) orelse {
                            return .{ .value = .{ .void = {} } };
                        };
                        var func_env = Environment.init(env.allocator, env) catch {
                            return .{ .value = .{ .void = {} } };
                        };
                        defer func_env.deinit();
                        func_env.setVar("this", .{ .js_object = obj }) catch {};
                        const iter = switch (func_node.*) {
                            .FunctionDeclaration => |f| evaluate(f.body, &func_env) catch {
                                return .{ .value = .{ .void = {} } };
                            },
                            .ArrowFunction => |f| evaluate(f.body, &func_env) catch {
                                return .{ .value = .{ .void = {} } };
                            },
                            else => return .{ .value = .{ .void = {} } },
                        };
                        if (iter == .iterator) {
                            iter_consumed = true;
                            while (true) {
                                const result = iter.iterator.next(env.allocator, &env.arrays, &env.objects);
                                if (result != .js_object) break;
                                const r_obj = result.js_object;
                                const done_opt = r_obj.properties.get("done");
                                const done = if (done_opt) |d| d else Types.Value{ .boolean = false };
                                if (done == .boolean and done.boolean) break;
                                const value_opt = r_obj.properties.get("value");
                                const value = if (value_opt) |v| v else Types.Value{ .void = {} };
                                new_array.elements.append(env.allocator, value) catch {
                                    return .{ .value = .{ .void = {} } };
                                };
                            }
                        } else if (iter == .js_object) {
                            // Iterator protocol: js_object with next() method
                            iter_consumed = true;
                            consumeIteratorProtocol(iter.js_object, new_array, env) catch {
                                return .{ .value = .{ .void = {} } };
                            };
                        }
                    } else if (iter_val == .iterator) {
                        iter_consumed = true;
                        while (true) {
                            const result = iter_val.iterator.next(env.allocator, &env.arrays, &env.objects);
                            if (result != .js_object) break;
                            const r_obj = result.js_object;
                            const done_opt = r_obj.properties.get("done");
                            const done = if (done_opt) |d| d else Types.Value{ .boolean = false };
                            if (done == .boolean and done.boolean) break;
                            const value_opt = r_obj.properties.get("value");
                            const value = if (value_opt) |v| v else Types.Value{ .void = {} };
                            new_array.elements.append(env.allocator, value) catch {
                                return .{ .value = .{ .void = {} } };
                            };
                        }
                    } else if (iter_val == .js_object) {
                        // Iterator protocol: direct js_object with next() method
                        iter_consumed = true;
                        consumeIteratorProtocol(iter_val.js_object, new_array, env) catch {
                            return .{ .value = .{ .void = {} } };
                        };
                    }
                }
            }

            // Fallback to length-based iteration
            if (!iter_consumed) {
                if (obj.properties.get("length")) |len_val| {
                    const len = switch (len_val) {
                        .integer => |n| @as(usize, @intCast(@max(0, n))),
                        .float => |n| @as(usize, @intCast(@max(0, @as(i64, @intFromFloat(n))))),
                        else => null,
                    };
                    if (len) |n| {
                        var buf: [32]u8 = undefined;
                        var i: usize = 0;
                        while (i < n) {
                            const key = std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
                            const elem_opt = obj.properties.get(key);
                            const elem = if (elem_opt) |e| e else Types.Value{ .void = {} };
                            new_array.elements.append(env.allocator, elem) catch {
                                return .{ .value = .{ .void = {} } };
                            };
                            i += 1;
                        }
                    }
                }
            }
        },
        else => {},
    }

    const map_fn_arg = if (args.len > 1) args[1] else Types.Value{ .void = {} };
    const this_arg = if (args.len > 2) args[2] else Types.Value{ .void = {} };

    if (map_fn_arg != .void) {
        const func_node = getFuncNode(map_fn_arg, env) orelse {
            new_array.deinit();
            return .{ .value = .{ .void = {} } };
        };

        const func_params: []const []const u8 = switch (func_node.*) {
            .FunctionDeclaration => |f| f.parameters,
            .ArrowFunction => |f| f.parameters,
            else => {
                new_array.deinit();
                return .{ .value = .{ .void = {} } };
            },
        };
        const func_body: *Ast.Node = switch (func_node.*) {
            .FunctionDeclaration => |f| f.body,
            .ArrowFunction => |f| f.body,
            else => {
                new_array.deinit();
                return .{ .value = .{ .void = {} } };
            },
        };

        var func_env = Environment.init(env.allocator, env) catch {
            return .{ .value = .{ .void = {} } };
        };
        defer func_env.deinit();

        for (new_array.elements.items, 0..) |elem, i| {
            func_env.return_hit = false;
            if (func_params.len > 0) func_env.setVar(func_params[0], elem) catch {};
            if (func_params.len > 1) func_env.setVar(func_params[1], .{ .integer = @intCast(i) }) catch {};
            if (this_arg != .void) {
                func_env.setVar("this", this_arg) catch {};
            }

            const mapped = evaluate(func_body, &func_env) catch {
                return .{ .value = .{ .void = {} } };
            };
            new_array.elements.items[i] = mapped;
        }
    }

    env.arrays.append(env.allocator, new_array) catch {
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .array = new_array } };
}

fn createTestDoubleFunc(allocator: std.mem.Allocator) !*Ast.Node {
    const body = try allocator.create(Ast.Node);
    body.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .Plus,
        .right = try allocator.create(Ast.Node),
    } };
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = "x" } };
    body.BinaryExpression.right.* = .{ .Identifier = .{ .name = "x" } };

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{"x"}),
        .body = body,
    } };
    return func_node;
}

fn destroyTestFunc(allocator: std.mem.Allocator, func_node: *Ast.Node) void {
    if (func_node.* == .ArrowFunction) {
        allocator.free(func_node.ArrowFunction.parameters);
        const body = func_node.ArrowFunction.body;
        if (body.* == .BinaryExpression) {
            allocator.destroy(body.BinaryExpression.left);
            allocator.destroy(body.BinaryExpression.right);
        }
        allocator.destroy(body);
        allocator.destroy(func_node);
    }
}

const testing = std.testing;

test "from creates array from string" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const str = try allocator.dupe(u8, "foo");
    env.owned_strings.append(allocator, str) catch {};

    var args = [_]Types.Value{.{ .string = str }};
    const result = From(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try testing.expectEqualSlices(u8, "f", result.value.array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "o", result.value.array.elements.items[1].string);
    try testing.expectEqualSlices(u8, "o", result.value.array.elements.items[2].string);
}

test "from creates array from existing array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const source = try Ast.ArrayObject.init(allocator);
    defer source.deinit();
    try source.elements.append(allocator, .{ .integer = 1 });
    try source.elements.append(allocator, .{ .integer = 2 });
    try source.elements.append(allocator, .{ .integer = 3 });

    var args = [_]Types.Value{.{ .array = source }};
    const result = From(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try testing.expectEqual(@as(i64, 1), result.value.array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 3), result.value.array.elements.items[2].integer);
}

test "from with map function" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const source = try Ast.ArrayObject.init(allocator);
    defer source.deinit();
    try source.elements.append(allocator, .{ .integer = 1 });
    try source.elements.append(allocator, .{ .integer = 2 });
    try source.elements.append(allocator, .{ .integer = 3 });

    const func_node = try createTestDoubleFunc(allocator);
    defer destroyTestFunc(allocator, func_node);
    try env.setFunction("double", func_node);

    var args = [_]Types.Value{ .{ .array = source }, .{ .string = "double" } };
    const result = From(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(i64, 2), result.value.array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 4), result.value.array.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 6), result.value.array.elements.items[2].integer);
}

test "from creates array from iterator" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const source = try Ast.ArrayObject.init(allocator);
    try env.arrays.append(allocator, source);
    try source.elements.append(allocator, .{ .integer = 10 });
    try source.elements.append(allocator, .{ .integer = 20 });
    try source.elements.append(allocator, .{ .integer = 30 });

    const iter = try Ast.ArrayIterator.initValues(allocator, source);
    try env.iterators.append(allocator, iter);

    var args = [_]Types.Value{.{ .iterator = iter }};
    const result = From(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try testing.expectEqual(@as(i64, 10), result.value.array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 20), result.value.array.elements.items[1].integer);
    try testing.expectEqual(@as(i64, 30), result.value.array.elements.items[2].integer);
}

test "from creates array from array-like object" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const obj = try Ast.ObjectValue.init(allocator);
    try env.objects.append(allocator, obj);
    try obj.properties.put("length", .{ .integer = 3 });
    const a = try allocator.dupe(u8, "a");
    const b = try allocator.dupe(u8, "b");
    const c = try allocator.dupe(u8, "c");
    env.owned_strings.append(allocator, a) catch {};
    env.owned_strings.append(allocator, b) catch {};
    env.owned_strings.append(allocator, c) catch {};
    try obj.properties.put("0", .{ .string = a });
    try obj.properties.put("1", .{ .string = b });
    try obj.properties.put("2", .{ .string = c });

    var args = [_]Types.Value{.{ .js_object = obj }};
    const result = From(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 3), result.value.array.elements.items.len);
    try testing.expectEqualSlices(u8, "a", result.value.array.elements.items[0].string);
    try testing.expectEqualSlices(u8, "b", result.value.array.elements.items[1].string);
    try testing.expectEqualSlices(u8, "c", result.value.array.elements.items[2].string);
}

test "from empty args returns empty array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const result = From(&[_]Types.Value{}, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 0), result.value.array.elements.items.len);
}

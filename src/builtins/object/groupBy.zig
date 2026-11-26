const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;
const evaluate = @import("../../evaluator.zig").evaluate;

/// Coerce a Value into a property-key string for use as an Object key.
/// Mirrors `ToPropertyKey → ToString` for non-symbol primitives, but
/// symbol keys are NOT preserved here — those require special handling
/// in `js_object` (prefix `@@sym_`) which is documented as future work.
fn toPropertyKey(v: Ast.Value, env: *Environment) ![]const u8 {
    return switch (v) {
        .string => |s| s,
        .integer => |i| blk: {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
            const owned = try env.allocator.dupe(u8, s);
            env.owned_strings.append(env.allocator, owned) catch {};
            break :blk owned;
        },
        .float => |f| blk: {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.OutOfMemory;
            const owned = try env.allocator.dupe(u8, s);
            env.owned_strings.append(env.allocator, owned) catch {};
            break :blk owned;
        },
        .boolean => |b| if (b) "true" else "false",
        .null => "null",
        .void => "undefined",
        else => "[object]",
    };
}

/// Find an existing bucket array for `key` in `result.properties`. Returns
/// the stored bucket array (a `.array` value) or null if absent.
fn findBucket(result_obj: *Ast.ObjectValue, key: []const u8) ?Ast.Value {
    if (result_obj.properties.get(key)) |v| {
        if (v == .array) return v;
    }
    return null;
}

/// `Object.groupBy(items, callbackFn)` — ES2024 static method.
/// Groups elements of `items` into a new Object, where each key is the
/// callback's return value coerced to a property key string. Items where
/// the callback returns `undefined` or `null` are excluded.
///
/// Currently only array inputs are supported (same limitation as Map.groupBy).
pub fn GroupBy(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    const items = args[0];
    const callback = args[1];

    const result_obj = Ast.ObjectValue.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.objects.append(env.allocator, result_obj) catch {
        result_obj.deinit();
        return .{ .value = .{ .void = {} } };
    };

    if (items != .array) return .{ .value = .{ .js_object = result_obj } };

    // Resolve callback to AST node.
    const func_node: *Ast.Node = switch (callback) {
        .string => |s| env.getFunction(s) orelse return .{ .value = .{ .js_object = result_obj } },
        .function => |f| @as(*Ast.Node, @ptrCast(@alignCast(f))),
        .closure => |cl| @as(*Ast.Node, @ptrCast(@alignCast(cl.func_node))),
        else => return .{ .value = .{ .js_object = result_obj } },
    };
    const func_params: []const []const u8 = switch (func_node.*) {
        .FunctionDeclaration => |f| f.parameters,
        .ArrowFunction => |f| f.parameters,
        else => return .{ .value = .{ .js_object = result_obj } },
    };
    const func_body: *Ast.Node = switch (func_node.*) {
        .FunctionDeclaration => |f| f.body,
        .ArrowFunction => |f| f.body,
        else => return .{ .value = .{ .js_object = result_obj } },
    };

    var func_env = Environment.initCallable(env.allocator, env, callback) catch {
        return .{ .value = .{ .js_object = result_obj } };
    };
    defer func_env.deinit();

    for (items.array.elements.items, 0..) |element, i| {
        if (element == .hole) continue;
        func_env.return_hit = false;
        if (func_params.len > 0) func_env.setVar(func_params[0], element) catch {};
        if (func_params.len > 1) func_env.setVar(func_params[1], Ast.Value{ .integer = @intCast(i) }) catch {};
        if (func_params.len > 2) func_env.setVar(func_params[2], items) catch {};

        const key_value = evaluate(func_body, &func_env) catch return .{ .value = .{ .void = {} } };
        // Propagate user-callback throws (evaluate may set throw_hit without
        // returning a Zig error, so check AFTER evaluate as well).
        if (func_env.throw_hit) {
            env.throw_hit = true;
            env.throw_value = func_env.throw_value;
            return .{ .value = .{ .void = {} } };
        }

        // Per ES2024: only undefined EXCLUDES an item; null is coerced via
        // ToPropertyKey → "null" and is a valid property key.
        if (key_value == .void) continue;

        const key_str = toPropertyKey(key_value, env) catch continue;

        if (findBucket(result_obj, key_str)) |bucket| {
            bucket.array.elements.append(env.allocator, element) catch {};
        } else {
            const bucket = Ast.ArrayObject.init(env.allocator) catch continue;
            env.arrays.append(env.allocator, bucket) catch {
                bucket.deinit();
                continue;
            };
            bucket.elements.append(env.allocator, element) catch {};
            result_obj.properties.put(key_str, Ast.Value{ .array = bucket }) catch {};
        }
    }

    return .{ .value = .{ .js_object = result_obj } };
}

const testing = std.testing;

fn mkItem(env: *Environment, name: []const u8, grade: []const u8) !*Ast.ObjectValue {
    const alloc = env.allocator;
    const obj = try Ast.ObjectValue.init(alloc);
    const n = try alloc.dupe(u8, name);
    const g = try alloc.dupe(u8, grade);
    env.owned_strings.append(alloc, n) catch {};
    env.owned_strings.append(alloc, g) catch {};
    try obj.properties.put("name", Ast.Value{ .string = n });
    try obj.properties.put("grade", Ast.Value{ .string = g });
    return obj;
}

test "Object.groupBy groups by string key" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const items = try Ast.ArrayObject.init(allocator);
    defer items.deinit();

    const alice = try mkItem(&env, "Alice", "A");
    env.objects.append(allocator, alice) catch {};
    try items.elements.append(allocator, Ast.Value{ .js_object = alice });

    const bob = try mkItem(&env, "Bob", "B");
    env.objects.append(allocator, bob) catch {};
    try items.elements.append(allocator, Ast.Value{ .js_object = bob });

    const charlie = try mkItem(&env, "Charlie", "A");
    env.objects.append(allocator, charlie) catch {};
    try items.elements.append(allocator, Ast.Value{ .js_object = charlie });

    // Define callback fn(item) { return item.grade; }
    const body = try allocator.create(Ast.Node);
    body.* = .{ .MemberAccess = .{
        .object = try allocator.create(Ast.Node),
        .property = "grade",
    } };
    body.MemberAccess.object.* = .{ .Identifier = .{ .name = "item" } };

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{"item"}),
        .body = body,
    } };
    defer {
        allocator.free(func_node.ArrowFunction.parameters);
        allocator.destroy(body.MemberAccess.object);
        allocator.destroy(body);
        allocator.destroy(func_node);
    }
    try env.setFunction("getGrade", func_node);

    var args = [_]Types.Value{
        .{ .array = items },
        .{ .string = "getGrade" },
    };
    const result = GroupBy(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .js_object);
    const out = result.value.js_object;

    const grade_a = out.properties.get("A") orelse {
        try testing.expect(false);
        return;
    };
    try testing.expect(grade_a == .array);
    try testing.expectEqual(@as(usize, 2), grade_a.array.elements.items.len);

    const grade_b = out.properties.get("B") orelse {
        try testing.expect(false);
        return;
    };
    try testing.expectEqual(@as(usize, 1), grade_b.array.elements.items.len);
}

test "Object.groupBy excludes items where callback returns null/undefined" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const items = try Ast.ArrayObject.init(allocator);
    defer items.deinit();
    try items.elements.append(allocator, .{ .integer = -1 });
    try items.elements.append(allocator, .{ .integer = 0 });
    try items.elements.append(allocator, .{ .integer = 1 });

    // Callback returns "neg" for <0, "zero" for 0, null for >0 (excluded).
    // We use a simple "is positive?" predicate implemented via a single
    // conditional expression to keep the test minimal.
    const null_node = try allocator.create(Ast.Node);
    null_node.* = Ast.Node{ .NullLiteral = .{} };
    const kept_node = try allocator.create(Ast.Node);
    kept_node.* = Ast.Node{ .StringLiteral = .{ .value = "kept" } };
    const body = try allocator.create(Ast.Node);
    body.* = .{ .ConditionalExpression = .{
        .condition = try allocator.create(Ast.Node),
        .consequent = null_node,
        .alternate = kept_node,
    } };
    body.ConditionalExpression.condition.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .GreaterThan,
        .right = try allocator.create(Ast.Node),
    } };
    body.ConditionalExpression.condition.BinaryExpression.left.* = .{ .Identifier = .{ .name = "n" } };
    body.ConditionalExpression.condition.BinaryExpression.right.* = .{ .IntegerLiteral = .{ .value = 0 } };

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{"n"}),
        .body = body,
    } };
    defer {
        allocator.free(func_node.ArrowFunction.parameters);
        allocator.destroy(body.ConditionalExpression.condition.BinaryExpression.left);
        allocator.destroy(body.ConditionalExpression.condition.BinaryExpression.right);
        allocator.destroy(body.ConditionalExpression.condition);
        allocator.destroy(body.ConditionalExpression.consequent);
        allocator.destroy(body.ConditionalExpression.alternate);
        allocator.destroy(body);
        allocator.destroy(func_node);
    }
    try env.setFunction("bucket", func_node);

    var args = [_]Types.Value{
        .{ .array = items },
        .{ .string = "bucket" },
    };
    const result = GroupBy(&args, &env);

    try testing.expect(result == .value);
    const out = result.value.js_object;
    const kept = out.properties.get("kept") orelse {
        try testing.expect(false);
        return;
    };
    try testing.expectEqual(@as(usize, 2), kept.array.elements.items.len);
    try testing.expectEqual(@as(i64, -1), kept.array.elements.items[0].integer);
    try testing.expectEqual(@as(i64, 0), kept.array.elements.items[1].integer);
}

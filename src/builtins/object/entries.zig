const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn Entries(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) {
        const arr = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
        env.arrays.append(env.allocator, arr) catch {
            arr.deinit();
            return .{ .value = .{ .void = {} } };
        };
        return .{ .value = .{ .array = arr } };
    }

    const obj = args[0];
    if (obj != .js_object) {
        const arr = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
        env.arrays.append(env.allocator, arr) catch {
            arr.deinit();
            return .{ .value = .{ .void = {} } };
        };
        return .{ .value = .{ .array = arr } };
    }

    const result = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.arrays.append(env.allocator, result) catch {
        result.deinit();
        return .{ .value = .{ .void = {} } };
    };

    const ordered = obj.js_object.getForInKeys(env.allocator, &env.arrays) catch {
        return .{ .value = .{ .void = {} } };
    };
    for (ordered.elements.items) |key_val| {
        const key = key_val.string;
        const v = obj.js_object.properties.get(key) orelse continue;

        const pair = Ast.ArrayObject.init(env.allocator) catch continue;
        env.arrays.append(env.allocator, pair) catch {
            pair.deinit();
            continue;
        };

        pair.elements.append(env.allocator, Types.Value{ .string = key }) catch {};
        pair.elements.append(env.allocator, v) catch {};

        result.elements.append(env.allocator, Types.Value{ .array = pair }) catch {
            pair.deinit();
        };
    }

    return .{ .value = .{ .array = result } };
}

const testing = std.testing;

test "Object.entries - basic object" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const obj = Ast.ObjectValue.init(allocator) catch return;
    defer obj.deinit();
    obj.properties.put("a", Types.Value{ .integer = 1 }) catch {};
    obj.properties.put("b", Types.Value{ .integer = 2 }) catch {};

    var args = [_]Types.Value{.{ .js_object = obj }};
    const result = Entries(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 2), result.value.array.elements.items.len);
}
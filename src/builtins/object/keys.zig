const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;
const typedArrayMod = @import("../typedarray.zig");

pub fn Keys(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
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

    if (typedArrayMod.isTypedArray(obj)) {
        const arr = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
        env.arrays.append(env.allocator, arr) catch {
            arr.deinit();
            return .{ .value = .{ .void = {} } };
        };
        typedArrayMod.appendForInKeys(obj, env, arr);
        return .{ .value = .{ .array = arr } };
    }

    const keys = obj.js_object.getForInKeys(env.allocator, &env.arrays) catch {
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .array = keys } };
}

const testing = std.testing;

test "Object.keys - basic object" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const obj = Ast.ObjectValue.init(allocator) catch return;
    defer obj.deinit();
    obj.properties.put("a", Types.Value{ .integer = 1 }) catch {};
    obj.properties.put("b", Types.Value{ .integer = 2 }) catch {};

    var args = [_]Types.Value{.{ .js_object = obj }};
    const result = Keys(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 2), result.value.array.elements.items.len);
}
test "Object.keys follows integer-first order" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const obj = Ast.ObjectValue.init(allocator) catch return;
    defer obj.deinit();
    obj.properties.put("b", Types.Value{ .integer = 1 }) catch {};
    obj.properties.put("0", Types.Value{ .integer = 2 }) catch {};

    var args = [_]Types.Value{.{ .js_object = obj }};
    const result = Keys(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .array);
    try testing.expectEqual(@as(usize, 2), result.value.array.elements.items.len);
    try testing.expectEqualStrings("0", result.value.array.elements.items[0].string);
    try testing.expectEqualStrings("b", result.value.array.elements.items[1].string);
}

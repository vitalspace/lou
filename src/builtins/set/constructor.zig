const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;
const getSet = @import("set_utils.zig").getSet;
const getValues = @import("set_utils.zig").getValues;
const valuesEqual = @import("set_utils.zig").valuesEqual;

pub fn SetConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const obj = Ast.ObjectValue.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };

    const values_arr = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, values_arr) catch {
        values_arr.deinit();
        return .{ .value = .{ .void = {} } };
    };

    obj.properties.put("@@type", .{ .string = "Set" }) catch {};
    obj.properties.put("values", .{ .array = values_arr }) catch {};

    if (args.len >= 1) {
        const source = args[0];
        if (source == .array) {
            for (source.array.elements.items) |elem| {
                var found = false;
                for (values_arr.elements.items) |existing| {
                    if (valuesEqual(existing, elem)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    values_arr.elements.append(env.allocator, elem) catch {};
                }
            }
        } else if (source == .js_object) {
            if (source.js_object.properties.get("length")) |len_val| {
                const len: usize = switch (len_val) {
                    .integer => |n| @intCast(@max(0, n)),
                    .float => |n| @intCast(@max(0, @as(i64, @intFromFloat(n)))),
                    else => 0,
                };
                var buf: [32]u8 = undefined;
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    const key = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                    const elem = source.js_object.properties.get(key) orelse Types.Value{ .void = {} };
                    var found = false;
                    for (values_arr.elements.items) |existing| {
                        if (valuesEqual(existing, elem)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        values_arr.elements.append(env.allocator, elem) catch {};
                    }
                }
            }
        } else if (source == .string) {
            var found = false;
            for (values_arr.elements.items) |existing| {
                if (valuesEqual(existing, source)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                values_arr.elements.append(env.allocator, source) catch {};
            }
        }
    }

    return .{ .value = .{ .js_object = obj } };
}

const testing = std.testing;

test "Set constructor creates empty set" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const result = SetConstructor(&.{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .js_object);
    const obj = result.value.js_object;
    try testing.expect(obj.properties.get("@@type") != null);
    try testing.expectEqualSlices(u8, "Set", obj.properties.get("@@type").?.string);
}

test "Set from array" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const arr = try Ast.ArrayObject.init(allocator);
    env.arrays.append(allocator, arr) catch {};
    try arr.elements.append(allocator, .{ .integer = 1 });
    try arr.elements.append(allocator, .{ .integer = 2 });
    try arr.elements.append(allocator, .{ .integer = 3 });

    var src_args = [_]Types.Value{.{ .array = arr }};
    const set_val = SetConstructor(&src_args, &env).value;
    const values = getValues(set_val) orelse unreachable;
    try testing.expectEqual(@as(usize, 3), values.elements.items.len);
}
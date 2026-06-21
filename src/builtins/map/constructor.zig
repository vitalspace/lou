const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn MapConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const obj = Ast.ObjectValue.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };

    const entries_arr = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, entries_arr) catch {
        entries_arr.deinit();
        return .{ .value = .{ .void = {} } };
    };

    obj.properties.put("@@type", .{ .string = "Map" }) catch {};
    obj.properties.put("entries", .{ .array = entries_arr }) catch {};

    if (args.len >= 1) {
        const source = args[0];
        if (source == .array) {
            var i: usize = 0;
            while (i < source.array.elements.items.len) : (i += 1) {
                const elem = source.array.elements.items[i];
                if (elem == .array and elem.array.elements.items.len >= 2) {
                    const pair = Ast.ArrayObject.init(env.allocator) catch continue;
                    env.arrays.append(env.allocator, pair) catch {
                        pair.deinit();
                        continue;
                    };
                    pair.elements.append(env.allocator, elem.array.elements.items[0]) catch {};
                    pair.elements.append(env.allocator, elem.array.elements.items[1]) catch {};
                    entries_arr.elements.append(env.allocator, .{ .array = pair }) catch {};
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
                    const key_str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                    const elem = source.js_object.properties.get(key_str) orelse Types.Value{ .void = {} };
                    if (elem == .array and elem.array.elements.items.len >= 2) {
                        const pair = Ast.ArrayObject.init(env.allocator) catch continue;
                        env.arrays.append(env.allocator, pair) catch {
                            pair.deinit();
                            continue;
                        };
                        pair.elements.append(env.allocator, elem.array.elements.items[0]) catch {};
                        pair.elements.append(env.allocator, elem.array.elements.items[1]) catch {};
                        entries_arr.elements.append(env.allocator, .{ .array = pair }) catch {};
                    }
                }
            }
        }
    }

    return .{ .value = .{ .js_object = obj } };
}

const testing = std.testing;

test "Map constructor creates empty map" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const result = MapConstructor(&.{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .js_object);
    const obj = result.value.js_object;
    try testing.expect(obj.properties.get("@@type") != null);
    try testing.expectEqualSlices(u8, "Map", obj.properties.get("@@type").?.string);
}

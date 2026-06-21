const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const map_utils = @import("map_utils.zig");

pub fn MapSet(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = map_utils.getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = map_utils.getEntries(map_val) orelse return .{ .value = .{ .void = {} } };

    if (args.len >= 3) {
        const key = args[1];
        const value = args[2];

        if (map_utils.findEntryIndex(entries, key)) |idx| {
            const existing_pair = entries.elements.items[idx];
            if (existing_pair == .array and existing_pair.array.elements.items.len >= 2) {
                existing_pair.array.elements.items[1] = value;
            }
        } else {
            const pair = Ast.ArrayObject.init(env.allocator) catch {
                return .{ .value = map_val };
            };
            env.arrays.append(env.allocator, pair) catch {
                pair.deinit();
                return .{ .value = map_val };
            };
            pair.elements.append(env.allocator, key) catch {};
            pair.elements.append(env.allocator, value) catch {};
            entries.elements.append(env.allocator, .{ .array = pair }) catch {};
        }
    }

    return .{ .value = map_val };
}

const testing = std.testing;
const MapConstructor = @import("constructor.zig").MapConstructor;

test "Map set and get" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const map_val = MapConstructor(&.{}, &env).value;
    var s1 = [_]Types.Value{ map_val, .{ .integer = 1 }, .{ .string = "one" } };
    _ = MapSet(&s1, &env);
    var s2 = [_]Types.Value{ map_val, .{ .integer = 2 }, .{ .string = "two" } };
    _ = MapSet(&s2, &env);
    try testing.expectEqual(@as(usize, 2), map_utils.getEntries(map_val).?.elements.items.len);
}

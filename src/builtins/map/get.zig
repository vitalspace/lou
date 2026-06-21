const std = @import("std");
const Types = @import("../../types/types.zig");
const map_utils = @import("map_utils.zig");

pub fn MapGet(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const map_val = map_utils.getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = map_utils.getEntries(map_val) orelse return .{ .value = .{ .void = {} } };

    if (args.len >= 2) {
        const key = args[1];
        if (map_utils.findEntryIndex(entries, key)) |idx| {
            const pair = entries.elements.items[idx];
            if (pair == .array and pair.array.elements.items.len >= 2) {
                return .{ .value = pair.array.elements.items[1] };
            }
        }
    }

    return .{ .value = .{ .void = {} } };
}

const testing = std.testing;
const MapConstructor = @import("constructor.zig").MapConstructor;
const MapSet = @import("set.zig").MapSet;

test "Map get returns stored value" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const map_val = MapConstructor(&.{}, &env).value;
    var s1 = [_]Types.Value{ map_val, .{ .integer = 1 }, .{ .string = "one" } };
    _ = MapSet(&s1, &env);
    var s2 = [_]Types.Value{ map_val, .{ .integer = 2 }, .{ .string = "two" } };
    _ = MapSet(&s2, &env);

    var g1 = [_]Types.Value{ map_val, .{ .integer = 1 } };
    const v1 = MapGet(&g1, &env);
    try testing.expect(v1.value == .string);
    try testing.expectEqualSlices(u8, "one", v1.value.string);

    var g3 = [_]Types.Value{ map_val, .{ .integer = 3 } };
    const v3 = MapGet(&g3, &env);
    try testing.expect(v3.value == .void);
}

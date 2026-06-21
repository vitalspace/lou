const std = @import("std");
const Types = @import("../../types/types.zig");
const map_utils = @import("map_utils.zig");

pub fn MapDelete(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = map_utils.getMap(args) orelse return .{ .value = .{ .boolean = false } };
    const entries = map_utils.getEntries(map_val) orelse return .{ .value = .{ .boolean = false } };

    if (args.len >= 2) {
        const key = args[1];
        if (map_utils.findEntryIndex(entries, key)) |idx| {
            _ = entries.elements.orderedRemove(idx);
            return .{ .value = .{ .boolean = true } };
        }
    }

    _ = env;
    return .{ .value = .{ .boolean = false } };
}

const testing = std.testing;
const MapConstructor = @import("constructor.zig").MapConstructor;
const MapSet = @import("set.zig").MapSet;
const MapHas = @import("has.zig").MapHas;

test "Map delete" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const map_val = MapConstructor(&.{}, &env).value;
    var a1 = [_]Types.Value{ map_val, .{ .integer = 1 }, .{ .string = "one" } };
    _ = MapSet(&a1, &env);
    var a2 = [_]Types.Value{ map_val, .{ .integer = 2 }, .{ .string = "two" } };
    _ = MapSet(&a2, &env);

    var del = [_]Types.Value{ map_val, .{ .integer = 1 } };
    try testing.expect(MapDelete(&del, &env).value.boolean);
    var has = [_]Types.Value{ map_val, .{ .integer = 1 } };
    try testing.expect(!MapHas(&has, &env).value.boolean);

    var not_del = [_]Types.Value{ map_val, .{ .integer = 99 } };
    try testing.expect(!MapDelete(&not_del, &env).value.boolean);
}

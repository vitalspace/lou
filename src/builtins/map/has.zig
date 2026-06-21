const std = @import("std");
const Types = @import("../../types/types.zig");
const map_utils = @import("map_utils.zig");

pub fn MapHas(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const map_val = map_utils.getMap(args) orelse return .{ .value = .{ .boolean = false } };
    const entries = map_utils.getEntries(map_val) orelse return .{ .value = .{ .boolean = false } };

    if (args.len >= 2) {
        const key = args[1];
        if (map_utils.findEntryIndex(entries, key)) |_| {
            return .{ .value = .{ .boolean = true } };
        }
    }

    return .{ .value = .{ .boolean = false } };
}

const testing = std.testing;
const MapConstructor = @import("constructor.zig").MapConstructor;
const MapSet = @import("set.zig").MapSet;

test "Map has" {
    const allocator = testing.allocator;
    var env = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const map_val = MapConstructor(&.{}, &env).value;
    var sa = [_]Types.Value{ map_val, .{ .integer = 1 }, .{ .string = "one" } };
    _ = MapSet(&sa, &env);

    var ha1 = [_]Types.Value{ map_val, .{ .integer = 1 } };
    try testing.expect(MapHas(&ha1, &env).value.boolean);
    var ha2 = [_]Types.Value{ map_val, .{ .integer = 2 } };
    try testing.expect(!MapHas(&ha2, &env).value.boolean);
}

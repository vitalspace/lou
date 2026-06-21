const std = @import("std");
const Types = @import("../../types/types.zig");
const map_utils = @import("map_utils.zig");

pub fn MapClear(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = map_utils.getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = map_utils.getEntries(map_val) orelse return .{ .value = .{ .void = {} } };
    entries.elements.clearRetainingCapacity();
    _ = env;
    return .{ .value = map_val };
}

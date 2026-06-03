const Types = @import("../../types/types.zig");
const getSet = @import("set_utils.zig").getSet;
const getValues = @import("set_utils.zig").getValues;

pub fn SetClear(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(set_val) orelse return .{ .value = .{ .void = {} } };
    values.elements.clearRetainingCapacity();
    _ = env;
    return .{ .value = set_val };
}
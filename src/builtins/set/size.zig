const Types = @import("../../types/types.zig");
const getSet = @import("set_utils.zig").getSet;
const getValues = @import("set_utils.zig").getValues;

pub fn SetSize(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .integer = 0 } };
    const values = getValues(set_val) orelse return .{ .value = .{ .integer = 0 } };
    return .{ .value = .{ .integer = @intCast(values.elements.items.len) } };
}
const Types = @import("../../types/types.zig");
const getSet = @import("set_utils.zig").getSet;
const getValues = @import("set_utils.zig").getValues;
const valuesEqual = @import("set_utils.zig").valuesEqual;

pub fn SetHas(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .boolean = false } };
    const values = getValues(set_val) orelse return .{ .value = .{ .boolean = false } };

    if (args.len > 1) {
        const search_val = args[1];
        for (values.elements.items) |existing| {
            if (valuesEqual(existing, search_val)) {
                return .{ .value = .{ .boolean = true } };
            }
        }
    }

    return .{ .value = .{ .boolean = false } };
}
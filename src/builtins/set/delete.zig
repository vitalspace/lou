const Types = @import("../../types/types.zig");
const getSet = @import("set_utils.zig").getSet;
const getValues = @import("set_utils.zig").getValues;
const valuesEqual = @import("set_utils.zig").valuesEqual;

pub fn SetDelete(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    const set_val = getSet(args) orelse return .{ .value = .{ .boolean = false } };
    const values = getValues(set_val) orelse return .{ .value = .{ .boolean = false } };

    if (args.len > 1) {
        const search_val = args[1];
        var i: usize = 0;
        while (i < values.elements.items.len) {
            if (valuesEqual(values.elements.items[i], search_val)) {
                _ = values.elements.orderedRemove(i);
                return .{ .value = .{ .boolean = true } };
            }
            i += 1;
        }
    }

    return .{ .value = .{ .boolean = false } };
}
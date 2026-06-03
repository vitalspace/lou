const Types = @import("../../types/types.zig");
const getSet = @import("set_utils.zig").getSet;
const getValues = @import("set_utils.zig").getValues;
const valuesEqual = @import("set_utils.zig").valuesEqual;

pub fn SetAdd(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(set_val) orelse return .{ .value = .{ .void = {} } };

    if (args.len > 1) {
        const new_val = args[1];
        var found = false;
        for (values.elements.items) |existing| {
            if (valuesEqual(existing, new_val)) {
                found = true;
                break;
            }
        }
        if (!found) {
            values.elements.append(env.allocator, new_val) catch {};
        }
    }

    return .{ .value = set_val };
}
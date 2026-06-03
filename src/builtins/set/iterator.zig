const Types = @import("../../types/types.zig");
const SetValues = @import("values.zig").SetValues;

pub fn SetIterator(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return SetValues(args, env);
}
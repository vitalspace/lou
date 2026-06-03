const Types = @import("../../types/types.zig");
const SetValues = @import("values.zig").SetValues;

pub fn SetKeys(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return SetValues(args, env);
}
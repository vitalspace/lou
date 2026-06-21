const std = @import("std");
const Types = @import("../../types/types.zig");
const MapEntries = @import("entries.zig").MapEntries;

pub fn MapIterator(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return MapEntries(args, env);
}

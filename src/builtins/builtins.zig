const std = @import("std");
const Types = @import("../types/types.zig");
const BUILTIN_OBJECTS = @import("./builtinObjects.zig").BUILTIN_OBJECTS;

/// Inicializa el hashmap de objetos builtin
pub fn initBuiltinObjects(allocator: std.mem.Allocator) !std.StringHashMap(*const Types.BuiltinObjectImpl) {
    var objects = std.StringHashMap(*const Types.BuiltinObjectImpl).init(allocator);
    comptime var i = 0;
    inline while (i < BUILTIN_OBJECTS.len) : (i += 1) {
        try objects.put(BUILTIN_OBJECTS[i].name, BUILTIN_OBJECTS[i]);
    }
    return objects;
}

const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Pop(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    if (args.len != 1) {
        return .{ .value = .{ .void = {} } }; // Error: pop necesita exactamente 1 argumento (el array)
    }

    const array_val = args[0];
    if (array_val != .array) {
        return .{ .value = .{ .void = {} } }; // Error: el argumento no es un array
    }

    // Remover y retornar el último elemento del array
    if (array_val.array.elements.items.len == 0) {
        return .{ .value = .{ .void = {} } }; // Array vacío, retornar undefined
    }

    const last_element = array_val.array.elements.pop();
    return .{ .value = last_element.? };
}

const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Push(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    if (args.len < 2) {
        return .{ .value = .{ .float = 0.0 } }; // Error: push necesita al menos 2 argumentos (array + elemento)
    }

    const array_val = args[0];
    if (array_val != .array) {
        return .{ .value = .{ .float = 0.0 } }; // Error: primer argumento no es un array
    }

    // OPTIMIZACIÓN: Pre-alocar capacidad para todos los elementos a insertar
    const elements_to_add = args.len - 1;
    const current_len = array_val.array.elements.items.len;
    const new_total_len = current_len + elements_to_add;

    // Reservar capacidad exacta para evitar múltiples realocaciones
    array_val.array.elements.ensureTotalCapacity(array_val.array.allocator, new_total_len) catch {
        return .{ .value = .{ .float = 0.0 } };
    };

    // Agregar elementos usando appendAssumeCapacity (sin checks de capacidad)
    for (args[1..]) |arg| {
        array_val.array.elements.appendAssumeCapacity(arg);
    }

    // Retornar la nueva longitud (como en JavaScript)
    return .{ .value = .{ .float = @floatFromInt(array_val.array.elements.items.len) } };
}

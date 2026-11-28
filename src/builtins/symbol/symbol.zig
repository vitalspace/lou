const std = @import("std");
const Types = @import("../../types/types.zig");

/// Symbol does not follow the standard BuiltinObjectImpl pattern because it has
/// properties (well-known symbols) rather than callable methods, and the
/// BuiltinObjectImpl type only carries a methods table. Once BuiltinObjectImpl
/// grows a properties field, this module should be migrated to register through
/// builtinObjects.zig like every other namespace.
const SYMBOL_METHODS = [_]Types.BuiltinMethod{};

pub const SYMBOL_OBJECT = Types.BuiltinObjectImpl{
    .name = "Symbol",
    .methods = &SYMBOL_METHODS,
};

const WELL_KNOWN = [_]Types.WellKnownSymbol{
    .iterator,
    .match,
    .replace,
    .search,
    .split,
    .hasInstance,
    .toPrimitive,
    .toStringTag,
    .species,
    .dispose,
    .asyncDispose,
    .asyncIterator,
};

/// Populate `env` with the `Symbol` namespace and its well-known symbols.
/// Each well-known symbol is allocated into `env.symbols` and exposed as a
/// property of the returned js_object (e.g. `Symbol.iterator`).
pub fn initSymbolObject(env: *Types.Environment) !void {
    const allocator = env.allocator;

    const symbol_obj = try Types.ObjectValue.init(allocator);
    try env.objects.append(allocator, symbol_obj);

    inline for (WELL_KNOWN) |wk| {
        const name = @tagName(wk);
        const sym = try Types.SymbolValue.init(allocator, @intFromEnum(wk), name);
        try env.symbols.append(allocator, sym);
        try symbol_obj.properties.put(name, .{ .symbol = sym });
    }

    try env.setConstant("Symbol", .{ .js_object = symbol_obj });
}

const std = @import("std");
const Types = @import("../types/types.zig");

pub const WellKnownSymbolNames = struct {
    pub const iterator = "iterator";
    pub const match = "match";
    pub const replace = "replace";
    pub const search = "search";
    pub const split = "split";
    pub const hasInstance = "hasInstance";
    pub const toPrimitive = "toPrimitive";
    pub const toStringTag = "toStringTag";
    pub const species = "species";
};

pub fn initSimboloObject(env: *Types.Environment) !void {
    const allocator = env.allocator;

    const simbolo_obj = try Types.ObjectValue.init(allocator);
    try env.objects.append(allocator, simbolo_obj);

    {
        const sym = try Types.SymbolValue.init(allocator, @intFromEnum(Types.WellKnownSymbol.iterator), "iterator");
        try env.symbols.append(allocator, sym);
        try simbolo_obj.properties.put("iterator", .{ .symbol = sym });
    }
    {
        const sym = try Types.SymbolValue.init(allocator, @intFromEnum(Types.WellKnownSymbol.match), "match");
        try env.symbols.append(allocator, sym);
        try simbolo_obj.properties.put("match", .{ .symbol = sym });
    }
    {
        const sym = try Types.SymbolValue.init(allocator, @intFromEnum(Types.WellKnownSymbol.replace), "replace");
        try env.symbols.append(allocator, sym);
        try simbolo_obj.properties.put("replace", .{ .symbol = sym });
    }
    {
        const sym = try Types.SymbolValue.init(allocator, @intFromEnum(Types.WellKnownSymbol.search), "search");
        try env.symbols.append(allocator, sym);
        try simbolo_obj.properties.put("search", .{ .symbol = sym });
    }
    {
        const sym = try Types.SymbolValue.init(allocator, @intFromEnum(Types.WellKnownSymbol.split), "split");
        try env.symbols.append(allocator, sym);
        try simbolo_obj.properties.put("split", .{ .symbol = sym });
    }
    {
        const sym = try Types.SymbolValue.init(allocator, @intFromEnum(Types.WellKnownSymbol.hasInstance), "hasInstance");
        try env.symbols.append(allocator, sym);
        try simbolo_obj.properties.put("hasInstance", .{ .symbol = sym });
    }
    {
        const sym = try Types.SymbolValue.init(allocator, @intFromEnum(Types.WellKnownSymbol.toPrimitive), "toPrimitive");
        try env.symbols.append(allocator, sym);
        try simbolo_obj.properties.put("toPrimitive", .{ .symbol = sym });
    }
    {
        const sym = try Types.SymbolValue.init(allocator, @intFromEnum(Types.WellKnownSymbol.toStringTag), "toStringTag");
        try env.symbols.append(allocator, sym);
        try simbolo_obj.properties.put("toStringTag", .{ .symbol = sym });
    }
    {
        const sym = try Types.SymbolValue.init(allocator, @intFromEnum(Types.WellKnownSymbol.species), "species");
        try env.symbols.append(allocator, sym);
        try simbolo_obj.properties.put("species", .{ .symbol = sym });
    }

    try env.setConstant("Simbolo", .{ .js_object = simbolo_obj });
}

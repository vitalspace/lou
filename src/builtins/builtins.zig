const std = @import("std");
const Types = @import("../types/types.zig");
const Ast = @import("../ast.zig");
const BUILTIN_OBJECTS = @import("./builtinObjects.zig").BUILTIN_OBJECTS;
const SetConstructor = @import("./set/set.zig").SetConstructor;
const MapConstructor = @import("./map/map.zig").MapConstructor;

fn arrayConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) {
        const arr = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
        env.arrays.append(env.allocator, arr) catch {};
        return .{ .value = .{ .array = arr } };
    }

    if (args.len == 1) {
        const len = switch (args[0]) {
            .integer => |i| i,
            .float => |f| @as(i64, @intFromFloat(f)),
            else => {
                const arr = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
                env.arrays.append(env.allocator, arr) catch {};
                arr.elements.append(env.allocator, args[0]) catch {};
                return .{ .value = .{ .array = arr } };
            },
        };
        if (len < 0) return .{ .value = .{ .void = {} } };
        const arr = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
        env.arrays.append(env.allocator, arr) catch {};
        var i: usize = 0;
        while (i < @as(usize, @intCast(len))) : (i += 1) {
            arr.elements.append(env.allocator, .{ .void = {} }) catch {};
        }
        return .{ .value = .{ .array = arr } };
    }

    const arr = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.arrays.append(env.allocator, arr) catch {};
    for (args) |arg| {
        arr.elements.append(env.allocator, arg) catch {};
    }
    return .{ .value = .{ .array = arr } };
}

const BUILTIN_FUNCTIONS = [_]struct { name: []const u8, func: Types.BuiltinFn }{
    .{ .name = "Array", .func = arrayConstructor },
    .{ .name = "Set", .func = SetConstructor },
    .{ .name = "Map", .func = MapConstructor },
};

pub fn initBuiltins(allocator: std.mem.Allocator) !std.StringHashMap(Types.BuiltinFn) {
    var funcs = std.StringHashMap(Types.BuiltinFn).init(allocator);
    comptime var i = 0;
    inline while (i < BUILTIN_FUNCTIONS.len) : (i += 1) {
        try funcs.put(BUILTIN_FUNCTIONS[i].name, BUILTIN_FUNCTIONS[i].func);
    }
    return funcs;
}

pub fn initBuiltinObjects(allocator: std.mem.Allocator) !std.StringHashMap(*const Types.BuiltinObjectImpl) {
    var objects = std.StringHashMap(*const Types.BuiltinObjectImpl).init(allocator);
    comptime var i = 0;
    inline while (i < BUILTIN_OBJECTS.len) : (i += 1) {
        try objects.put(BUILTIN_OBJECTS[i].name, BUILTIN_OBJECTS[i]);
    }
    return objects;
}

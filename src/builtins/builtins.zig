const std = @import("std");
const Types = @import("../types/types.zig");
const Ast = @import("../ast.zig");
const BUILTIN_OBJECTS = @import("./builtinObjects.zig").BUILTIN_OBJECTS;
const SetConstructor = @import("./set/set.zig").SetConstructor;
const MapConstructor = @import("./map/map.zig").MapConstructor;
const BooleanConstructor = @import("./boolean/boolean.zig").BooleanConstructor;
const DateConstructor = @import("./date/constructor.zig").DateConstructor;
const DisposableStackConstructor = @import("./disposable/constructor.zig").DisposableStackConstructor;
const encodeUri = @import("./uri.zig").encodeUri;
const decodeUri = @import("./uri.zig").decodeUri;
const encodeUriComponent = @import("./uri.zig").encodeUriComponent;
const decodeUriComponent = @import("./uri.zig").decodeUriComponent;
const ErrorConstructor = @import("./error.zig").ErrorConstructor;
const TypeErrorConstructor = @import("./error.zig").TypeErrorConstructor;
const RangeErrorConstructor = @import("./error.zig").RangeErrorConstructor;
const ReferenceErrorConstructor = @import("./error.zig").ReferenceErrorConstructor;
const SyntaxErrorConstructor = @import("./error.zig").SyntaxErrorConstructor;
const EvalErrorConstructor = @import("./error.zig").EvalErrorConstructor;
const URIErrorConstructor = @import("./error.zig").URIErrorConstructor;
const FinalizationRegistryConstructor = @import("./finalization-registry.zig").FinalizationRegistryConstructor;
const WeakRefConstructor = @import("./weakref.zig").WeakRefConstructor;
const NumberConstructorFn = @import("./number/number.zig").NumberConstructor;
const StringConstructorFn = @import("./string/string.zig").StringConstructor;
const isFiniteFn = @import("./isfinite-isnan.zig").isFinite;
const isNaNFn = @import("./isfinite-isnan.zig").isNaN;
const parseIntFn = @import("./parseint-parsefloat.zig").parseInt;
const parseFloatFn = @import("./parseint-parsefloat.zig").parseFloat;
const BigIntConstructorFn = @import("./bigint/bigint.zig").BigIntConstructor;
const IntlConstructorFn = @import("./intl/intl.zig").IntlConstructor;
const RegExpConstructorFn = @import("./regex/regexp_constructor.zig").RegExpConstructor;

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
            arr.elements.append(env.allocator, .{ .hole = {} }) catch {};
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
    .{ .name = "Boolean", .func = BooleanConstructor },
    .{ .name = "Date", .func = DateConstructor },
    .{ .name = "DisposableStack", .func = DisposableStackConstructor },
    .{ .name = "encodeURI", .func = encodeUri },
    .{ .name = "decodeURI", .func = decodeUri },
    .{ .name = "encodeURIComponent", .func = encodeUriComponent },
    .{ .name = "decodeURIComponent", .func = decodeUriComponent },
    .{ .name = "Error", .func = ErrorConstructor },
    .{ .name = "TypeError", .func = TypeErrorConstructor },
    .{ .name = "RangeError", .func = RangeErrorConstructor },
    .{ .name = "ReferenceError", .func = ReferenceErrorConstructor },
    .{ .name = "SyntaxError", .func = SyntaxErrorConstructor },
    .{ .name = "EvalError", .func = EvalErrorConstructor },
    .{ .name = "URIError", .func = URIErrorConstructor },
    .{ .name = "FinalizationRegistry", .func = FinalizationRegistryConstructor },
    .{ .name = "WeakRef", .func = WeakRefConstructor },
    .{ .name = "Number", .func = NumberConstructorFn },
    .{ .name = "String", .func = StringConstructorFn },
    .{ .name = "isFinite", .func = isFiniteFn },
    .{ .name = "isNaN", .func = isNaNFn },
    .{ .name = "parseInt", .func = parseIntFn },
    .{ .name = "parseFloat", .func = parseFloatFn },
    .{ .name = "BigInt", .func = BigIntConstructorFn },
    .{ .name = "Intl", .func = IntlConstructorFn },
    .{ .name = "RegExp", .func = RegExpConstructorFn },
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

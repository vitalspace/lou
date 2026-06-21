const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

/// Bound function info extraída de un `js_object` con `@@type="Function"`.
/// Se usa tanto para `Function.prototype.bind` como para la invocación
/// del wrapper resultante.
pub const BoundFunctionInfo = struct {
    target: Types.Value,
    bound_this: Types.Value,
    bound_args: []const Types.Value,
};

/// Crea un `js_object` wrapper que representa una función ligada
/// (resultado de `fn.bind(thisArg, ...boundArgs)`).
///
/// El wrapper tiene:
///   - `@@type`       = `"Function"`
///   - `@@target`     = la función original (puede ser `.function` o
///                      otro wrapper ligado, permitiendo `bind().bind()`)
///   - `@@bound_this` = el `this` fijado
///   - `@@bound_args` = array con los argumentos pre-fijados
pub fn makeBoundFunction(
    env: *Types.Environment,
    target: Types.Value,
    bound_this: Types.Value,
    bound_args: []const Types.Value,
) *Types.ObjectValue {
    const obj = Types.ObjectValue.init(env.allocator) catch {
        @panic("OOM in makeBoundFunction");
    };
    errdefer obj.deinit();

    const tag = env.allocator.dupe(u8, "Function") catch {
        @panic("OOM in makeBoundFunction");
    };
    errdefer env.allocator.free(tag);
    env.owned_strings.append(env.allocator, tag) catch {};

    obj.properties.put("@@type", .{ .string = tag }) catch {};
    obj.properties.put("@@target", target) catch {};
    obj.properties.put("@@bound_this", bound_this) catch {};

    const arr = Ast.ArrayObject.init(env.allocator) catch {
        @panic("OOM in makeBoundFunction");
    };
    errdefer arr.deinit();
    env.arrays.append(env.allocator, arr) catch {};
    for (bound_args) |a| {
        arr.elements.append(env.allocator, a) catch {};
    }
    obj.properties.put("@@bound_args", .{ .array = arr }) catch {};

    env.objects.append(env.allocator, obj) catch {};
    return obj;
}

/// True si el objeto es un wrapper de función ligada.
pub fn isBoundFunction(obj: *const Types.ObjectValue) bool {
    const tag = obj.properties.get("@@type") orelse return false;
    if (tag != .string) return false;
    return std.mem.eql(u8, tag.string, "Function");
}

/// Extrae la información de un wrapper de función ligada. Retorna null
/// si el objeto no es un wrapper válido.
pub fn extractBoundFunction(obj: *const Types.ObjectValue) ?BoundFunctionInfo {
    if (!isBoundFunction(obj)) return null;
    const target = obj.properties.get("@@target") orelse return null;
    const maybe_this = obj.properties.get("@@bound_this");
    const bound_this: Types.Value = if (maybe_this) |v| v else .{ .void = {} };
    const bound_args_val = obj.properties.get("@@bound_args") orelse return null;
    if (bound_args_val != .array) return null;
    return .{
        .target = target,
        .bound_this = bound_this,
        .bound_args = bound_args_val.array.elements.items,
    };
}

const testing = std.testing;

test "makeBoundFunction + extractBoundFunction round trip" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    var fn_node: Ast.Node = .{ .FunctionDeclaration = .{
        .name = "",
        .parameters = &.{},
        .body = undefined,
    } };
    const target: Types.Value = .{ .function = @ptrCast(&fn_node) };
    const bound_this_obj = try Types.ObjectValue.init(testing.allocator);
    try env.objects.append(testing.allocator, bound_this_obj);
    const bound_this: Types.Value = .{ .js_object = bound_this_obj };
    const bound_args = [_]Types.Value{ .{ .integer = 1 }, .{ .integer = 2 } };

    const obj = makeBoundFunction(&env, target, bound_this, &bound_args);

    try testing.expect(isBoundFunction(obj));

    const info = extractBoundFunction(obj).?;
    try testing.expect(info.target == .function);
    try testing.expect(info.bound_this.js_object == bound_this.js_object);
    try testing.expectEqual(@as(usize, 2), info.bound_args.len);
    try testing.expectEqual(@as(i64, 1), info.bound_args[0].integer);
    try testing.expectEqual(@as(i64, 2), info.bound_args[1].integer);
}

test "extractBoundFunction returns null for non-function js_object" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const obj = try Types.ObjectValue.init(testing.allocator);
    env.objects.append(testing.allocator, obj) catch {};

    try testing.expect(extractBoundFunction(obj) == null);
    try testing.expect(!isBoundFunction(obj));
}

test "extractBoundFunction rejects other @@type" {
    var env = try @import("../../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const obj = try Types.ObjectValue.init(testing.allocator);
    env.objects.append(testing.allocator, obj) catch {};

    const tag = try testing.allocator.dupe(u8, "Set");
    env.owned_strings.append(testing.allocator, tag) catch {};
    try obj.properties.put("@@type", .{ .string = tag });

    try testing.expect(extractBoundFunction(obj) == null);
    try testing.expect(!isBoundFunction(obj));
}

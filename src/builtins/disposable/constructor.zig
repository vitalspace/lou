const std = @import("std");
const Types = @import("../../types/types.zig");

/// `new DisposableStack()` constructor.
/// Creates a `.js_object` with `@@type="DisposableStack"` and an empty `_callbacks` array.
pub fn DisposableStackConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = args;
    const alloc = env.allocator;

    const obj = Types.ObjectValue.init(alloc) catch return .{ .value = .{ .void = {} } };
    env.objects.append(alloc, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    obj.properties.put("@@type", .{ .string = "DisposableStack" }) catch {};

    return .{ .value = .{ .js_object = obj } };
}

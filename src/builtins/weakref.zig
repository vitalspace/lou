const std = @import("std");
const Types = @import("../types/types.zig");

/// `new WeakRef(target)` constructor.
/// Creates a `.js_object` with `@@type="WeakRef"` and stores the target.
/// Target must be an object (non-primitive); throws TypeError otherwise.
/// Since Lou has no GC, deref() will always return the stored target.
pub fn WeakRefConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const alloc = env.allocator;

    const obj = Types.ObjectValue.init(alloc) catch return .{ .value = .{ .void = {} } };
    env.objects.append(alloc, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };

    obj.properties.put("@@type", .{ .string = "WeakRef" }) catch {};

    // Validate and store the target (must be an object)
    if (args.len == 0) {
        _ = @import("error.zig").throwError(env, "TypeError", .{ .string = "WeakRef: target must be an object" });
        return .{ .value = .{ .void = {} } };
    }
    const target = args[0];
    if (target != .js_object and target != .object and target != .array and
        target != .function and target != .closure and target != .generator)
    {
        _ = @import("error.zig").throwError(env, "TypeError", .{ .string = "WeakRef: target must be an object" });
        return .{ .value = .{ .void = {} } };
    }
    obj.properties.put("_target", target) catch {};

    return .{ .value = .{ .js_object = obj } };
}

/// `WeakRef.prototype.deref()`
/// Returns the stored target, or undefined if it has been collected.
/// Since Lou has no GC, always returns the stored target.
pub fn Deref(args: []Types.Value, _env: *Types.Environment) Types.BuiltinResult {
    _ = _env;
    if (args.len < 1) return .{ .value = .{ .void = {} } };

    const this_val = args[0];
    if (this_val != .js_object) return .{ .value = .{ .void = {} } };
    const this_obj = this_val.js_object;

    // Verify @@type
    const type_tag = this_obj.properties.get("@@type");
    if (type_tag == null or type_tag.? != .string or !std.mem.eql(u8, type_tag.?.string, "WeakRef")) {
        return .{ .value = .{ .void = {} } };
    }

    // Return the stored target or undefined
    if (this_obj.properties.get("_target")) |target| {
        return .{ .value = target };
    }
    return .{ .value = .{ .void = {} } };
}

/// Instance methods on `WeakRef.prototype`.
pub const WEAKREF_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "deref", .func = Deref },
};

pub const WEAKREF_OBJECT = Types.BuiltinObjectImpl{
    .name = "WeakRef",
    .methods = &WEAKREF_METHODS,
};

const std = @import("std");
const Types = @import("../../types/types.zig");
const ast = @import("../../ast.zig");
const cleanup = @import("cleanup.zig");

/// Validate args[0] is a DisposableStack js_object, returning the object or null.
pub fn requireStack(args: []Types.Value) ?*Types.ObjectValue {
    if (args.len < 1) return null;
    if (args[0] != .js_object) return null;
    const obj = args[0].js_object;
    const tag = obj.properties.get("@@type");
    if (tag == null or tag.? != .string or !std.mem.eql(u8, tag.?.string, "DisposableStack")) return null;
    return obj;
}

/// Get or create the internal callbacks array.
fn getCallbacks(obj: *Types.ObjectValue, env: *Types.Environment) !*ast.ArrayObject {
    if (obj.properties.get("_callbacks")) |cbs| {
        if (cbs == .array) return cbs.array;
    }
    const arr = try ast.ArrayObject.init(env.allocator);
    errdefer arr.deinit();
    try env.arrays.append(env.allocator, arr);
    try obj.properties.put("_callbacks", .{ .array = arr });
    return arr;
}

/// Get the disposed flag (defaults to false).
pub fn isDisposed(obj: *Types.ObjectValue) bool {
    if (obj.properties.get("_disposed")) |d| {
        return d == .boolean and d.boolean;
    }
    return false;
}

/// Push a callback record onto the stack.
fn pushCallback(obj: *Types.ObjectValue, env: *Types.Environment, kind: []const u8, value: ?Types.Value, callback: ?Types.Value) !void {
    const cbs = try getCallbacks(obj, env);
    const record = try Types.ObjectValue.init(env.allocator);
    errdefer record.deinit();
    try env.objects.append(env.allocator, record);
    try record.properties.put("kind", .{ .string = kind });
    if (value) |v| try record.properties.put("value", v);
    if (callback) |cb| try record.properties.put("callback", cb);
    try cbs.elements.append(env.allocator, .{ .js_object = record });
}

/// DisposableStack.prototype.use(value) — registers value; calls value[Symbol.dispose]() on dispose.
pub fn Use(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const stack = requireStack(args) orelse return .{ .value = .{ .void = {} } };
    if (isDisposed(stack)) return .{ .value = .{ .void = {} } };
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    pushCallback(stack, env, "use", args[1], null) catch return .{ .value = .{ .void = {} } };
    return .{ .value = args[1] };
}

/// DisposableStack.prototype.adopt(value, onDispose) — registers value with custom cleanup callback.
pub fn Adopt(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const stack = requireStack(args) orelse return .{ .value = .{ .void = {} } };
    if (isDisposed(stack)) return .{ .value = .{ .void = {} } };
    if (args.len < 3) return .{ .value = .{ .void = {} } };
    pushCallback(stack, env, "adopt", args[1], args[2]) catch return .{ .value = .{ .void = {} } };
    return .{ .value = args[1] };
}

/// DisposableStack.prototype.defer(onDispose) — registers a cleanup callback.
pub fn Defer(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const stack = requireStack(args) orelse return .{ .value = .{ .void = {} } };
    if (isDisposed(stack)) return .{ .value = .{ .void = {} } };
    if (args.len < 2) return .{ .value = .{ .void = {} } };
    pushCallback(stack, env, "defer", null, args[1]) catch return .{ .value = .{ .void = {} } };
    return .{ .value = .{ .void = {} } };
}

/// DisposableStack.prototype.dispose() — executes all registered cleanups in reverse order.
pub fn Dispose(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const stack = requireStack(args) orelse return .{ .value = .{ .void = {} } };
    if (isDisposed(stack)) return .{ .value = .{ .void = {} } };
    cleanup.executeDispose(stack, env);
    return .{ .value = .{ .void = {} } };
}

/// DisposableStack.prototype.move() — creates a new stack with all resources,
/// clears the current stack, and returns the new stack.
pub fn Move(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const stack = requireStack(args) orelse return .{ .value = .{ .void = {} } };
    if (isDisposed(stack)) return .{ .value = .{ .void = {} } };

    // Create a new empty DisposableStack.
    const new_obj = Types.ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    errdefer new_obj.deinit();
    env.objects.append(env.allocator, new_obj) catch {
        new_obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    new_obj.properties.put("@@type", .{ .string = "DisposableStack" }) catch {};

    // Move callbacks array from old to new.
    var moved_callbacks = false;
    if (stack.properties.get("_callbacks")) |cbs_val| {
        if (cbs_val == .array) {
            new_obj.properties.put("_callbacks", cbs_val) catch {
                new_obj.deinit();
                return .{ .value = .{ .void = {} } };
            };
            _ = stack.properties.remove("_callbacks");
            moved_callbacks = true;
        }
    }
    if (!moved_callbacks) {
        _ = getCallbacks(new_obj, env) catch {};
    }

    // Mark old stack as disposed.
    stack.properties.put("_disposed", .{ .boolean = true }) catch {};

    return .{ .value = .{ .js_object = new_obj } };
}

/// DisposableStack.prototype.disposed — getter property.
pub fn GetDisposed(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    const stack = requireStack(args) orelse return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = isDisposed(stack) } };
}

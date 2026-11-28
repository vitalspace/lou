const std = @import("std");
const Types = @import("../types/types.zig");

const throwError = @import("error.zig").throwError;

pub const TYPE_KEY = "@@type";
pub const TARGET_KEY = "@@proxy_target";
pub const HANDLER_KEY = "@@proxy_handler";

const PROXY_METHODS = [_]Types.BuiltinMethod{};

pub const PROXY_OBJECT = Types.BuiltinObjectImpl{
    .name = "Proxy",
    .methods = &PROXY_METHODS,
    .properties = &.{
        .{ .name = "name", .value = Types.Value{ .string = "Proxy" } },
    },
};

/// Returns true when `value` is a Proxy wrapper created by `new Proxy(...)`.
pub fn isProxy(value: Types.Value) bool {
    if (value != .js_object) return false;
    const tag = value.js_object.properties.get(TYPE_KEY) orelse return false;
    return tag == .string and std.mem.eql(u8, tag.string, "Proxy");
}

/// Returns the wrapped target of a proxy, if `value` is a proxy.
pub fn getTarget(value: Types.Value) ?Types.Value {
    if (!isProxy(value)) return null;
    return value.js_object.properties.get(TARGET_KEY);
}

/// Returns the handler object of a proxy, if `value` is a proxy.
pub fn getHandler(value: Types.Value) ?Types.Value {
    if (!isProxy(value)) return null;
    return value.js_object.properties.get(HANDLER_KEY);
}

fn isObjectLike(value: Types.Value) bool {
    return switch (value) {
        .js_object, .array, .object, .regexp, .function, .closure, .generator => true,
        else => false,
    };
}

fn isCallableTarget(value: Types.Value) bool {
    return switch (value) {
        .function, .closure, .generator => true,
        .js_object => value.js_object.properties.get("@@callable") != null or
            value.js_object.properties.get("@@class") != null or
            value.js_object.properties.get("@@bound_this") != null,
        else => false,
    };
}

/// `new Proxy(target, handler)`.
///
/// The proxy is represented as a regular `.js_object` carrying internal
/// `@@proxy_target` and `@@proxy_handler` properties. Keeping it as a normal
/// object avoids adding a new `Value` variant and keeps every existing switch
/// exhaustive.
pub fn ProxyConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) {
        _ = throwError(env, "TypeError", .{ .string = "Cannot create proxy with a non-object as target or handler" });
        return .{ .value = .{ .void = {} } };
    }

    const target = args[0];
    const handler = args[1];
    if (!isObjectLike(target) or !isObjectLike(handler)) {
        _ = throwError(env, "TypeError", .{ .string = "Cannot create proxy with a non-object as target or handler" });
        return .{ .value = .{ .void = {} } };
    }

    const alloc = env.allocator;
    const obj = Types.ObjectValue.init(alloc) catch return .{ .value = .{ .void = {} } };

    obj.properties.put(TYPE_KEY, .{ .string = "Proxy" }) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    obj.properties.put(TARGET_KEY, target) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    obj.properties.put(HANDLER_KEY, handler) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    if (isCallableTarget(target)) {
        obj.properties.put("@@callable", .{ .boolean = true }) catch {
            obj.deinit();
            return .{ .value = .{ .void = {} } };
        };
    }

    env.objects.append(alloc, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };
    return .{ .value = .{ .js_object = obj } };
}

test "Proxy constructor stores target and handler" {
    const allocator = std.testing.allocator;
    var env = try @import("../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const target = try Types.ObjectValue.init(allocator);
    defer target.deinit();
    const handler = try Types.ObjectValue.init(allocator);
    defer handler.deinit();

    var args = [_]Types.Value{ .{ .js_object = target }, .{ .js_object = handler } };
    const result = ProxyConstructor(args[0..], &env);
    try std.testing.expect(result == .value);
    try std.testing.expect(isProxy(result.value));
    try std.testing.expect(getTarget(result.value).?.js_object == target);
    try std.testing.expect(getHandler(result.value).?.js_object == handler);
}

test "Proxy constructor rejects primitive targets" {
    const allocator = std.testing.allocator;
    var env = try @import("../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const handler = try Types.ObjectValue.init(allocator);
    defer handler.deinit();

    var args = [_]Types.Value{ .{ .integer = 1 }, .{ .js_object = handler } };
    _ = ProxyConstructor(args[0..], &env);
    try std.testing.expect(env.throw_hit);
}

test "Proxy constructor marks callable targets" {
    const allocator = std.testing.allocator;
    var env = try @import("../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    const target = try Types.ObjectValue.init(allocator);
    defer target.deinit();
    try target.properties.put("@@class", .{ .boolean = true });
    const handler = try Types.ObjectValue.init(allocator);
    defer handler.deinit();

    var args = [_]Types.Value{ .{ .js_object = target }, .{ .js_object = handler } };
    const result = ProxyConstructor(args[0..], &env);
    try std.testing.expect(isProxy(result.value));
    try std.testing.expect(result.value.js_object.properties.get("@@callable") != null);
}

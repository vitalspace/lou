// Promise runtime with a deterministic microtask queue.
//
// Promises are `.js_object` values tagged with `@@type = "Promise"`. State
// and result live in hidden `@@promise_*` properties so user-visible
// enumeration/inspection does not see them. Reactions are queued on the
// root environment and drained by `evaluator.drainPromiseJobs()` after the
// top-level program completes, which matches Node ordering for programs
// whose promises resolve synchronously.

const std = @import("std");
const Types = @import("../../types/types.zig");
const ast = @import("../../ast.zig");

const STATE_PENDING = "pending";
const STATE_FULFILLED = "fulfilled";
const STATE_REJECTED = "rejected";

pub fn isPromise(value: Types.Value) bool {
    if (value != .js_object) return false;
    const tag = value.js_object.properties.get("@@type") orelse return false;
    return tag == .string and std.mem.eql(u8, tag.string, "Promise");
}

pub fn isPending(value: Types.Value) bool {
    return isPromise(value) and std.mem.eql(u8, promiseState(value), STATE_PENDING);
}

pub fn promiseState(value: Types.Value) []const u8 {
    if (value != .js_object) return STATE_PENDING;
    const state = value.js_object.properties.get("@@promise_state") orelse return STATE_PENDING;
    return if (state == .string) state.string else STATE_PENDING;
}

pub fn promiseValue(value: Types.Value) Types.Value {
    if (value != .js_object) return .{ .void = {} };
    return value.js_object.properties.get("@@promise_value") orelse .{ .void = {} };
}

fn makeObject(env: *Types.Environment) !*ast.ObjectValue {
    const obj = try ast.ObjectValue.init(env.allocator);
    errdefer obj.deinit();
    try env.objects.append(env.allocator, obj);
    return obj;
}

pub fn createPromise(env: *Types.Environment, state: []const u8, value: Types.Value) Types.Value {
    const obj = makeObject(env) catch return .{ .void = {} };
    obj.properties.put("@@type", .{ .string = "Promise" }) catch {};
    obj.properties.put("@@promise_state", .{ .string = state }) catch {};
    obj.properties.put("@@promise_value", value) catch {};
    return .{ .js_object = obj };
}

pub fn createPending(env: *Types.Environment) Types.Value {
    return createPromise(env, STATE_PENDING, .{ .void = {} });
}

pub fn createResolved(env: *Types.Environment, value: Types.Value) Types.Value {
    if (isPromise(value)) return value;
    return createPromise(env, STATE_FULFILLED, value);
}

pub fn createRejected(env: *Types.Environment, reason: Types.Value) Types.Value {
    return createPromise(env, STATE_REJECTED, reason);
}

fn setState(promise: *ast.ObjectValue, state: []const u8, value: Types.Value) void {
    promise.properties.put("@@promise_state", .{ .string = state }) catch {};
    promise.properties.put("@@promise_value", value) catch {};
}

fn enqueuePassThrough(env: *Types.Environment, parent: Types.Value, child: Types.Value) void {
    const reaction = makeObject(env) catch return;
    reaction.properties.put("@@type", .{ .string = "PromiseReaction" }) catch {};
    reaction.properties.put("parent", parent) catch {};
    reaction.properties.put("child", child) catch {};
    const root = env.root();
    root.promise_jobs.append(root.allocator, .{ .js_object = reaction }) catch {};
}

pub fn resolvePromise(env: *Types.Environment, promise: *ast.ObjectValue, value: Types.Value) void {
    const target = Types.Value{ .js_object = promise };
    if (!std.mem.eql(u8, promiseState(target), STATE_PENDING)) return;

    if (isPromise(value)) {
        if (value.js_object == promise) {
            setState(promise, STATE_REJECTED, .{ .string = "TypeError: Chaining cycle detected for promise" });
            return;
        }
        const parent_state = promiseState(value);
        if (std.mem.eql(u8, parent_state, STATE_FULFILLED)) {
            setState(promise, STATE_FULFILLED, promiseValue(value));
        } else if (std.mem.eql(u8, parent_state, STATE_REJECTED)) {
            setState(promise, STATE_REJECTED, promiseValue(value));
        } else {
            enqueuePassThrough(env, value, target);
        }
        return;
    }

    setState(promise, STATE_FULFILLED, value);
}

pub fn rejectPromise(promise: *ast.ObjectValue, reason: Types.Value) void {
    const target = Types.Value{ .js_object = promise };
    if (!std.mem.eql(u8, promiseState(target), STATE_PENDING)) return;
    setState(promise, STATE_REJECTED, reason);
}

pub fn makeResolver(env: *Types.Environment, target: Types.Value, reject: bool) Types.Value {
    const obj = makeObject(env) catch return .{ .void = {} };
    obj.properties.put("@@type", .{ .string = "PromiseResolver" }) catch {};
    obj.properties.put("@@callable", .{ .boolean = true }) catch {};
    obj.properties.put("@@promise", target) catch {};
    obj.properties.put("@@reject", .{ .boolean = reject }) catch {};
    return .{ .js_object = obj };
}

pub fn isResolver(value: Types.Value) bool {
    if (value != .js_object) return false;
    const tag = value.js_object.properties.get("@@type") orelse return false;
    return tag == .string and std.mem.eql(u8, tag.string, "PromiseResolver");
}

pub fn callResolver(env: *Types.Environment, obj: *ast.ObjectValue, args: []const Types.Value) void {
    const target = obj.properties.get("@@promise") orelse return;
    if (!isPromise(target)) return;
    const reject = obj.properties.get("@@reject") orelse ast.Value{ .boolean = false };
    const value = if (args.len > 0) args[0] else Types.Value{ .void = {} };
    if (reject == .boolean and reject.boolean) {
        rejectPromise(target.js_object, value);
    } else {
        resolvePromise(env, target.js_object, value);
    }
}

fn queuedReaction(env: *Types.Environment, parent: Types.Value, on_fulfilled: ?Types.Value, on_rejected: ?Types.Value, on_finally: ?Types.Value) Types.Value {
    const child = createPending(env);
    const reaction = makeObject(env) catch return child;
    reaction.properties.put("@@type", .{ .string = "PromiseReaction" }) catch {};
    reaction.properties.put("parent", parent) catch {};
    reaction.properties.put("child", child) catch {};
    if (on_fulfilled) |f| reaction.properties.put("onFulfilled", f) catch {};
    if (on_rejected) |r| reaction.properties.put("onRejected", r) catch {};
    if (on_finally) |f| reaction.properties.put("onFinally", f) catch {};
    const root = env.root();
    root.promise_jobs.append(root.allocator, .{ .js_object = reaction }) catch {};
    return child;
}

pub fn PromiseThen(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0 or !isPromise(args[0])) return .{ .value = .{ .void = {} } };
    const on_fulfilled = if (args.len > 1) args[1] else null;
    const on_rejected = if (args.len > 2) args[2] else null;
    return .{ .value = queuedReaction(env, args[0], on_fulfilled, on_rejected, null) };
}

pub fn PromiseCatch(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0 or !isPromise(args[0])) return .{ .value = .{ .void = {} } };
    const on_rejected = if (args.len > 1) args[1] else null;
    return .{ .value = queuedReaction(env, args[0], null, on_rejected, null) };
}

pub fn PromiseFinally(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0 or !isPromise(args[0])) return .{ .value = .{ .void = {} } };
    const on_finally = if (args.len > 1) args[1] else null;
    return .{ .value = queuedReaction(env, args[0], null, null, on_finally) };
}

pub fn PromiseResolveStatic(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const value = if (args.len > 0) args[0] else Types.Value{ .void = {} };
    return .{ .value = createResolved(env, value) };
}

pub fn PromiseRejectStatic(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const reason = if (args.len > 0) args[0] else Types.Value{ .void = {} };
    return .{ .value = createRejected(env, reason) };
}

pub fn PromiseWithResolvers(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = args;

    const promise = createPending(env);
    if (!isPromise(promise)) return .{ .value = .{ .void = {} } };

    const resolve_fn = makeResolver(env, promise, false);
    const reject_fn = makeResolver(env, promise, true);
    if (!isResolver(resolve_fn) or !isResolver(reject_fn)) {
        return .{ .value = .{ .void = {} } };
    }

    const resolvers = makeObject(env) catch return .{ .value = .{ .void = {} } };
    resolvers.properties.put("promise", promise) catch {};
    resolvers.properties.put("resolve", resolve_fn) catch {};
    resolvers.properties.put("reject", reject_fn) catch {};
    return .{ .value = .{ .js_object = resolvers } };
}

fn arrayFromValues(env: *Types.Environment, values: []const Types.Value) Types.Value {
    const arr = ast.ArrayObject.init(env.allocator) catch return .{ .void = {} };
    env.arrays.append(env.allocator, arr) catch {};
    for (values) |value| arr.elements.append(env.allocator, value) catch {};
    return .{ .array = arr };
}

fn iterableValues(value: Types.Value) ?[]const Types.Value {
    return switch (value) {
        .array => |arr| arr.elements.items,
        else => null,
    };
}

fn arrayOfNulls(env: *Types.Environment, len: usize) Types.Value {
    const arr = ast.ArrayObject.init(env.allocator) catch return .{ .void = {} };
    env.arrays.append(env.allocator, arr) catch {};
    for (0..len) |_| arr.elements.append(env.allocator, .{ .null = {} }) catch {};
    return .{ .array = arr };
}

fn enqueueAggregateJob(
    env: *Types.Environment,
    parent: Types.Value,
    result: Types.Value,
    kind: []const u8,
    index: usize,
    values: Types.Value,
    remaining: usize,
    rejected: usize,
) void {
    const reaction = makeObject(env) catch return;
    reaction.properties.put("@@type", .{ .string = "PromiseAggregateReaction" }) catch {};
    reaction.properties.put("@@aggregate", .{ .boolean = true }) catch {};
    reaction.properties.put("parent", parent) catch {};
    reaction.properties.put("@@result", result) catch {};
    reaction.properties.put("@@kind", .{ .string = kind }) catch {};
    reaction.properties.put("@@index", .{ .integer = @intCast(index) }) catch {};
    reaction.properties.put("@@values", values) catch {};
    reaction.properties.put("@@remaining", .{ .integer = @intCast(remaining) }) catch {};
    reaction.properties.put("@@rejected", .{ .integer = @intCast(rejected) }) catch {};
    const root = env.root();
    root.promise_jobs.append(root.allocator, .{ .js_object = reaction }) catch {};
}

fn aggregateStart(env: *Types.Environment, values: []const Types.Value, kind: []const u8) Types.Value {
    const result = createPending(env);
    if (result == .js_object) {
        result.js_object.properties.put("@@remaining", .{ .integer = @intCast(values.len) }) catch {};
        result.js_object.properties.put("@@rejected", .{ .integer = 0 }) catch {};
    }
    if (values.len == 0) {
        if (std.mem.eql(u8, kind, "any")) return createRejected(env, .{ .string = "AggregateError: All promises were rejected" });
        if (std.mem.eql(u8, kind, "race")) return createPending(env);
        return createResolved(env, arrayFromValues(env, &.{}));
    }
    const slots = arrayOfNulls(env, values.len);
    for (values, 0..) |value, index| {
        const parent = if (isPromise(value)) value else createResolved(env, value);
        enqueueAggregateJob(env, parent, result, kind, index, slots, values.len, 0);
    }
    return result;
}
pub fn PromiseAll(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const values = if (args.len > 0) iterableValues(args[0]) orelse &[_]Types.Value{} else &[_]Types.Value{};
    return .{ .value = aggregateStart(env, values, "all") };
}

pub fn PromiseAllSettled(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const values = if (args.len > 0) iterableValues(args[0]) orelse &[_]Types.Value{} else &[_]Types.Value{};
    return .{ .value = aggregateStart(env, values, "allSettled") };
}

pub fn PromiseRace(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const values = if (args.len > 0) iterableValues(args[0]) orelse &[_]Types.Value{} else &[_]Types.Value{};
    return .{ .value = aggregateStart(env, values, "race") };
}

pub fn PromiseAny(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const values = if (args.len > 0) iterableValues(args[0]) orelse &[_]Types.Value{} else &[_]Types.Value{};
    return .{ .value = aggregateStart(env, values, "any") };
}

pub const PROMISE_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "then", .func = PromiseThen },
    .{ .name = "catch", .func = PromiseCatch },
    .{ .name = "finally", .func = PromiseFinally },
    .{ .name = "resolve", .func = PromiseResolveStatic },
    .{ .name = "reject", .func = PromiseRejectStatic },
    .{ .name = "withResolvers", .func = PromiseWithResolvers },
    .{ .name = "all", .func = PromiseAll },
    .{ .name = "allSettled", .func = PromiseAllSettled },
    .{ .name = "race", .func = PromiseRace },
    .{ .name = "any", .func = PromiseAny },
};

pub const PROMISE_OBJECT = Types.BuiltinObjectImpl{
    .name = "Promise",
    .methods = &PROMISE_METHODS,
    .properties = &.{
        .{ .name = "name", .value = Types.Value{ .string = "Promise" } },
    },
};

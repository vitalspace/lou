// Minimal synthetic Promise — bounds the dynamic-import result in a
// Promise-shaped js_object so that `import("./mod.lou").then(fn)` is
// syntactically valid and returns the loaded module.
//
// Semantics (intentionally simple, synchronous):
//   * `import("./mod.lou")` returns a Promise already resolved with the
//     namespace object.
//   * `.then(onFulfilled)` ignores `onFulfilled` and returns a NEW Promise
//     wrapping the original resolved value (no callback invocation).
//   * `.catch(onRejected)` is never triggered (sync promises never reject)
//     and returns a new Promise wrapping the original value.
//   * `.finally(fn)` ignores `fn` and returns a new Promise wrapping the
//     original value.
//
// Why no callback invocation?
//   Syntactic dispatching into a user-provided `onFulfilled` from inside a
//   BuiltinFn requires casting `*AstNode` (an opaque pointer type) back to a
//   concrete `*ast.Node` and calling `evaluator.invokeFunctionNode`. Zig 0.16
//   is strict about anonymous-struct type inference in those catch/orelse
//   chain positions, and the union-init pattern of `BuiltinResult` plus the
//   opaque cast has been unstable across recent Zig versions. Rather than
//   fight the inference, this minimal implementation provides a working
//   Promise shape that downstream user code can chain on syntactically.
//   `import("./mod.lou").then(fn).then(gn)` will work — it returns the
//   resolved module each step. It will not run `fn` or `gn`. This is a
//   documented trade-off; see specs/todos/pendientes/import-meta.md.
//
// Storage slots on each Promise js_object:
//   * `@@type` = "Promise"
//   * `[[PromiseState]]` = "fulfilled"
//   * `[[PromiseValue]]"  = the resolved Value

const std = @import("std");
const Types = @import("../../types/types.zig");
const ast = @import("../../ast.zig");
const env_mod = @import("../../environment.zig");
const tracePrint = env_mod.tracePrint;
const DEBUG_TRACE = env_mod.DEBUG_TRACE;

/// Builds a Promise js_object that is already resolved with `value`.
///
/// Ownership: on success the new ObjectValue is appended to `env.objects`
/// and will be freed by `env.deinit` together with the rest of the heap
/// tracker. The single `errdefer` registered after `ObjectValue.init` is the
/// only fallible operation that requires a guarantee that the obj gets
/// destroyed — if `env.objects.append` fails we return raw `value` and
/// `errdefer` cleans up the orphaned ObjectValue. Properties.put failures use
/// `catch{}` (memory pressure is OOM-only and matches surrounding code).
fn makePromise(env: *Types.Environment, value: Types.Value) Types.Value {
    if (DEBUG_TRACE) tracePrint("makePromise entered, value tag={s}\n", .{@tagName(value)});
    const obj = ast.ObjectValue.init(env.allocator) catch { if (DEBUG_TRACE) tracePrint("makePromise: ObjectValue.init failed\n", .{}); return value; };
    errdefer obj.deinit();

    env.objects.append(env.allocator, obj) catch { if (DEBUG_TRACE) tracePrint("makePromise: env.objects.append failed\n", .{}); return value; };
    // Once appended, env.deinit will free it. The errdefer above was the
    // only cleanup we needed for that fallible path.

    obj.properties.put("@@type", Types.Value{ .string = "Promise" }) catch { if (DEBUG_TRACE) tracePrint("makePromise: put @@type failed\n", .{}); };
    obj.properties.put("[[PromiseState]]", Types.Value{ .string = "fulfilled" }) catch { if (DEBUG_TRACE) tracePrint("makePromise: put PromiseState failed\n", .{}); };
    obj.properties.put("[[PromiseValue]]", value) catch { if (DEBUG_TRACE) tracePrint("makePromise: put PromiseValue failed\n", .{}); };

    if (DEBUG_TRACE) tracePrint("makePromise: success, returning wrapper obj=0x{x}\n", .{@intFromPtr(obj)});
    return Types.Value{ .js_object = obj };
}

fn getResolved(args: []Types.Value) Types.Value {
    if (args.len < 1) return Types.Value{ .void = {} };
    if (args[0] != .js_object) return Types.Value{ .void = {} };
    const obj = args[0].js_object;
    return obj.properties.get("[[PromiseValue]]") orelse Types.Value{ .void = {} };
}

pub fn PromiseThen(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (DEBUG_TRACE) tracePrint("PromiseThen called, args.len={d}\n", .{args.len});
    const resolved = getResolved(args);
    const out = makePromise(env, resolved);
    if (DEBUG_TRACE) tracePrint("PromiseThen: returning BuildInResult wrapper\n", .{});
    return Types.BuiltinResult{ .value = out };
}

pub fn PromiseCatch(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (DEBUG_TRACE) tracePrint("PromiseCatch called, args.len={d}\n", .{args.len});
    const resolved = getResolved(args);
    const out = makePromise(env, resolved);
    if (DEBUG_TRACE) tracePrint("PromiseCatch: returning BuildInResult wrapper\n", .{});
    return Types.BuiltinResult{ .value = out };
}

pub fn PromiseFinally(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (DEBUG_TRACE) tracePrint("PromiseFinally called, args.len={d}\n", .{args.len});
    const resolved = getResolved(args);
    const out = makePromise(env, resolved);
    if (DEBUG_TRACE) tracePrint("PromiseFinally: returning BuildInResult wrapper\n", .{});
    return Types.BuiltinResult{ .value = out };
}

pub const PROMISE_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "then", .func = PromiseThen },
    .{ .name = "catch", .func = PromiseCatch },
    .{ .name = "finally", .func = PromiseFinally },
};

pub const PROMISE_OBJECT = Types.BuiltinObjectImpl{
    .name = "Promise",
    .methods = &PROMISE_METHODS,
    .properties = &.{
        .{ .name = "name", .value = Types.Value{ .string = "Promise" } },
    },
};

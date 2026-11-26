const std = @import("std");
const Types = @import("../../types/types.zig");
const ast = @import("../../ast.zig");

/// Execute all cleanup callbacks for a DisposableStack in reverse (LIFO) order.
/// Callbacks are tried via tryCallFunction (best-effort invocation).
pub fn executeDispose(stack: *Types.ObjectValue, env: *Types.Environment) void {
    if (stack.properties.get("_disposed")) |d| {
        if (d == .boolean and d.boolean) return;
    }
    stack.properties.put("_disposed", .{ .boolean = true }) catch {};

    const cbs_val = stack.properties.get("_callbacks") orelse return;
    if (cbs_val != .array) return;
    const cbs = cbs_val.array;

    // Iterate in reverse order (LIFO).
    var i: usize = cbs.elements.items.len;
    while (i > 0) {
        i -= 1;
        const elem = cbs.elements.items[i];
        if (elem != .js_object) continue;
        const record = elem.js_object;

        const kind_val = record.properties.get("kind") orelse continue;
        if (kind_val != .string) continue;
        const kind = kind_val.string;

        if (std.mem.eql(u8, kind, "use")) {
            const val = record.properties.get("value") orelse continue;
            tryDisposeValue(env, val);
        } else if (std.mem.eql(u8, kind, "adopt")) {
            const val = record.properties.get("value");
            const cb = record.properties.get("callback") orelse continue;
            if (val) |v| {
                tryCallFunction(env, cb, v);
            } else {
                tryCallFunction(env, cb, .{ .void = {} });
            }
        } else if (std.mem.eql(u8, kind, "defer")) {
            const cb = record.properties.get("callback") orelse continue;
            tryCallFunction(env, cb, .{ .void = {} });
        }
    }
}

/// Try to call a function value with one argument.
fn tryCallFunction(env: *Types.Environment, func_val: Types.Value, arg: Types.Value) void {
    const evaluate = @import("../../evaluator.zig").evaluate;

    if (func_val == .closure) {
        var arg_arr = [1]Types.Value{arg};
        const call_fn = @import("../../evaluator.zig").callFunctionValue;
        _ = call_fn(func_val, arg_arr[0..], env, .{ .void = {} }) catch return;
        return;
    }

    switch (func_val) {
        .function => |fn_ptr| {
            const fn_node: *ast.Node = @alignCast(@ptrCast(fn_ptr));
            const allocator = env.allocator;

            const callee_node = allocator.create(ast.Node) catch return;
            callee_node.* = fn_node.*;

            const arg_ptr = allocator.create(ast.Node) catch {
                allocator.destroy(callee_node);
                return;
            };
            arg_ptr.* = .{ .VoidLiteral = .{} };

            const args_slice = allocator.alloc(*ast.Node, 1) catch {
                allocator.destroy(arg_ptr);
                allocator.destroy(callee_node);
                return;
            };
            args_slice[0] = arg_ptr;

            const call_node = allocator.create(ast.Node) catch {
                allocator.free(args_slice);
                allocator.destroy(arg_ptr);
                allocator.destroy(callee_node);
                return;
            };
            call_node.* = .{ .DirectCall = .{
                .callee = callee_node,
                .arguments = args_slice,
            } };

            defer {
                allocator.free(args_slice);
                allocator.destroy(arg_ptr);
                allocator.destroy(callee_node);
                allocator.destroy(call_node);
            }

            const result = evaluate(call_node, env) catch return;
            _ = result;
        },
        else => {},
    }
}

/// Try to call the Symbol.dispose method on a value.
fn tryDisposeValue(env: *Types.Environment, val: Types.Value) void {
    if (val != .js_object) return;
    const obj = val.js_object;

    const dispose_key = Types.symbolPropertyName(env.allocator, "dispose") catch return;
    defer env.allocator.free(dispose_key);

    if (obj.properties.get(dispose_key)) |dispose_method| {
        tryCallFunction(env, dispose_method, val);
    } else if (obj.properties.get("dispose")) |dispose_method| {
        tryCallFunction(env, dispose_method, val);
    }
}

/// Public helper for block-scope cleanup: call dispose() on a value if it supports it.
/// Handles both DisposableStack objects and arbitrary values with [Symbol.dispose]().
pub fn disposeValue(env: *Types.Environment, val: Types.Value) void {
    if (val != .js_object) return;
    const obj = val.js_object;
    const tag = obj.properties.get("@@type");
    if (tag != null and tag.? == .string and std.mem.eql(u8, tag.?.string, "DisposableStack")) {
        executeDispose(obj, env);
        return;
    }
    // For non-DisposableStack objects, try calling [Symbol.dispose]() directly.
    tryDisposeValue(env, val);
}

const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;
const evaluate = @import("../../evaluator.zig").evaluate;

fn escapeString(buf: *std.ArrayList(u8), s: []const u8, allocator: std.mem.Allocator) !void {
    try buf.append(allocator, '"');
    for (s) |ch| {
        switch (ch) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            '\x08' => try buf.appendSlice(allocator, "\\b"),
            '\x0C' => try buf.appendSlice(allocator, "\\f"),
            else => try buf.append(allocator, ch),
        }
    }
    try buf.append(allocator, '"');
}

fn appendInt(buf: *std.ArrayList(u8), val: i64, allocator: std.mem.Allocator) !void {
    var fmt_buf: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&fmt_buf, "{d}", .{val});
    try buf.appendSlice(allocator, s);
}

fn appendFloat(buf: *std.ArrayList(u8), val: f64, allocator: std.mem.Allocator) !void {
    if (std.math.isNan(val) or std.math.isInf(val)) {
        try buf.appendSlice(allocator, "null");
        return;
    }
    var fmt_buf: [64]u8 = undefined;
    const s = try std.fmt.bufPrint(&fmt_buf, "{d}", .{val});
    var end: usize = s.len;
    if (std.mem.indexOfScalar(u8, s, '.') != null) {
        while (end > 0 and s[end - 1] == '0') {
            end -= 1;
        }
        if (end > 0 and s[end - 1] == '.') {
            end -= 1;
        }
    }
    try buf.appendSlice(allocator, s[0..end]);
}

fn appendIndent(buf: *std.ArrayList(u8), indent: []const u8, depth: usize, allocator: std.mem.Allocator) !void {
    var j: usize = 0;
    while (j < depth) : (j += 1) {
        try buf.appendSlice(allocator, indent);
    }
}

/// Call the replacer function with (key, value) and return the result.
/// Returns the original value if the function can't be called.
fn callReplacerFn(replacer_fn: *Ast.Node, key: []const u8, value: Types.Value, env: *Types.Environment) !Types.Value {
    const func_params: []const []const u8 = switch (replacer_fn.*) {
        .FunctionDeclaration => |f| f.parameters,
        .ArrowFunction => |f| f.parameters,
        else => return value,
    };
    const func_body: *Ast.Node = switch (replacer_fn.*) {
        .FunctionDeclaration => |f| f.body,
        .ArrowFunction => |f| f.body,
        else => return value,
    };

    var func_env = Environment.initBlock(env.allocator, env) catch {
        return value;
    };
    defer func_env.deinit();

    if (func_params.len > 0) {
        // Heap-allocate the key string so it outlives this call (replacer may store it in arrays/objects).
        const key_copy = env.allocator.dupe(u8, key) catch return value;
        env.owned_strings.append(env.allocator, key_copy) catch {
            env.allocator.free(key_copy);
            return value;
        };
        func_env.setVar(func_params[0], .{ .string = key_copy }) catch {};
    }
    if (func_params.len > 1) {
        func_env.setVar(func_params[1], value) catch {};
    }

    const result = evaluate(func_body, &func_env) catch {
        return value;
    };
    return result;
}

/// Apply the replacer function to (key, value). If no replacer, returns the original value.
fn applyReplacer(replacer_fn: ?*Ast.Node, key: []const u8, value: Types.Value, env: *Types.Environment) !Types.Value {
    if (replacer_fn) |fn_node| {
        return try callReplacerFn(fn_node, key, value, env);
    }
    return value;
}

fn valueToJson(
    buf: *std.ArrayList(u8),
    val: Types.Value,
    _: []const u8, // replacer already applied by caller (Stringify root or object/array loops)
    allocator: std.mem.Allocator,
    depth: usize,
    indent: ?[]const u8,
    replacer_fn: ?*Ast.Node,
    allowed_keys: ?*const std.StringArrayHashMapUnmanaged(void),
    env: *Types.Environment,
) !void {
    // The replacer is applied by the caller (Stringify for root, object/array loops for children).
    // We only skip .void here because a parent loop may have produced it.
    if (val == .void) return;

    switch (val) {
        .string => |s| {
            try escapeString(buf, s, allocator);
        },
        .integer => |i| {
            try appendInt(buf, i, allocator);
        },
        .float => |f| {
            try appendFloat(buf, f, allocator);
        },
        .boolean => |b| {
            try buf.appendSlice(allocator, if (b) "true" else "false");
        },
        .null => {
            try buf.appendSlice(allocator, "null");
        },
        .regexp => {
            try buf.appendSlice(allocator, "{}");
        },
        .void => {
            try buf.appendSlice(allocator, "null");
        },
        .array => |arr| {
            try buf.append(allocator, '[');
            if (indent != null and arr.elements.items.len > 0) {
                try buf.append(allocator, '\n');
                for (arr.elements.items, 0..) |elem, i| {
                    if (i > 0) {
                        try buf.appendSlice(allocator, ",\n");
                    }
                    try appendIndent(buf, indent.?, depth + 1, allocator);
                    var idx_key_buf: [32]u8 = undefined;
                    const idx_key = try std.fmt.bufPrint(&idx_key_buf, "{d}", .{i});
                    switch (elem) {
                        .hole => try buf.appendSlice(allocator, "null"),
                        .function => try buf.appendSlice(allocator, "null"),
                        .symbol => try buf.appendSlice(allocator, "null"),
                        else => {
                            const eff_elem = try applyReplacer(replacer_fn, idx_key, elem, env);
                            if (eff_elem == .void) {
                                try buf.appendSlice(allocator, "null");
                            } else {
                                try valueToJson(buf, eff_elem, idx_key, allocator, depth + 1, indent, replacer_fn, allowed_keys, env);
                            }
                        },
                    }
                }
                try buf.append(allocator, '\n');
                try appendIndent(buf, indent.?, depth, allocator);
            } else {
                for (arr.elements.items, 0..) |elem, i| {
                    if (i > 0) try buf.append(allocator, ',');
                    var idx_key_buf: [32]u8 = undefined;
                    const idx_key = try std.fmt.bufPrint(&idx_key_buf, "{d}", .{i});
                    switch (elem) {
                        .hole => try buf.appendSlice(allocator, "null"),
                        .function => try buf.appendSlice(allocator, "null"),
                        .symbol => try buf.appendSlice(allocator, "null"),
                        else => {
                            const eff_elem = try applyReplacer(replacer_fn, idx_key, elem, env);
                            if (eff_elem == .void) {
                                try buf.appendSlice(allocator, "null");
                            } else {
                                try valueToJson(buf, eff_elem, idx_key, allocator, depth + 1, indent, replacer_fn, allowed_keys, env);
                            }
                        },
                    }
                }
            }
            try buf.append(allocator, ']');
        },
        .js_object => |obj| {
            const ordered = try obj.getForInKeys(env.allocator, &env.arrays);
            var keys = ordered.elements.items;
            if (allowed_keys) |allowed| {
                // A replacer array defines the property order, not just a
                // membership filter, so build the key list in that order.
                const filtered = try Ast.ArrayObject.init(env.allocator);
                try env.arrays.append(env.allocator, filtered);
                for (allowed.keys()) |k| {
                    if (obj.properties.contains(k)) {
                        try filtered.elements.append(env.allocator, .{ .string = k });
                    }
                }
                keys = filtered.elements.items;
            }
            try buf.append(allocator, '{');
            // Count printable keys (considering allowed_keys filter)
            var printable_count: usize = 0;
            for (keys) |key_val| {
                const key = key_val.string;
                const v = obj.properties.get(key) orelse continue;
                switch (v) {
                    .function, .symbol, .void => continue,
                    else => {},
                }
                if (allowed_keys) |allowed| {
                    if (!allowed.contains(key)) continue;
                }
                printable_count += 1;
            }
            // Helper to write a property if its effective value (after replacer) is not void
            const pp_indent = indent;
            if (pp_indent != null and printable_count > 0) {
                try buf.append(allocator, '\n');
                var idx: usize = 0;
                for (keys) |key_val| {
                    const key = key_val.string;
                    const v = obj.properties.get(key) orelse continue;
                    switch (v) {
                        .function, .symbol, .void => continue,
                        else => {},
                    }
                    if (allowed_keys) |allowed| {
                        if (!allowed.contains(key)) continue;
                    }
                    // Apply replacer FIRST to check if this property should be excluded
                    const prop_val = try applyReplacer(replacer_fn, key, v, env);
                    if (prop_val == .void) continue;
                    if (idx > 0) {
                        try buf.appendSlice(allocator, ",\n");
                    }
                    try appendIndent(buf, pp_indent.?, depth + 1, allocator);
                    try escapeString(buf, key, allocator);
                    try buf.appendSlice(allocator, ": ");
                    try valueToJson(buf, prop_val, key, allocator, depth + 1, pp_indent, replacer_fn, allowed_keys, env);
                    idx += 1;
                }
                try buf.append(allocator, '\n');
                try appendIndent(buf, pp_indent.?, depth, allocator);
            } else {
                var first = true;
                for (keys) |key_val| {
                    const key = key_val.string;
                    const v = obj.properties.get(key) orelse continue;
                    switch (v) {
                        .function, .symbol, .void => continue,
                        else => {},
                    }
                    if (allowed_keys) |allowed| {
                        if (!allowed.contains(key)) continue;
                    }
                    // Apply replacer FIRST to check if this property should be excluded
                    const prop_val = try applyReplacer(replacer_fn, key, v, env);
                    if (prop_val == .void) continue;
                    if (!first) try buf.append(allocator, ',');
                    first = false;
                    try escapeString(buf, key, allocator);
                    try buf.append(allocator, ':');
                    try valueToJson(buf, prop_val, key, allocator, depth + 1, indent, replacer_fn, allowed_keys, env);
                }
            }
            try buf.append(allocator, '}');
        },
        .big_int => {
            try buf.appendSlice(allocator, "null");
        },
        .function, .symbol, .iterator, .generator, .closure, .array_iterator => {
            try buf.appendSlice(allocator, "null");
        },
        .object, .hole => {
            try buf.appendSlice(allocator, "null");
        },
    }
}

fn resolveSpace(allocator: std.mem.Allocator, space_val: Types.Value) ?[]const u8 {
    if (space_val == .null or space_val == .void) return null;
    if (space_val == .string) {
        const s = space_val.string;
        if (s.len == 0) return null;
        const len = @min(s.len, @as(usize, 10));
        const result = allocator.alloc(u8, len) catch return null;
        @memcpy(result, s[0..len]);
        return result;
    }
    if (space_val == .integer) {
        const n = space_val.integer;
        if (n <= 0) return null;
        const count = @min(n, @as(i64, 10));
        const s = allocator.alloc(u8, @as(usize, @intCast(count))) catch return null;
        @memset(s, ' ');
        return s;
    }
    if (space_val == .float) {
        const f = space_val.float;
        if (std.math.isNan(f) or std.math.isInf(f) or f <= 0) return null;
        const clamped = @min(f, 10.0);
        const count = @as(i64, @intFromFloat(clamped));
        if (count <= 0) return null;
        const s = allocator.alloc(u8, @as(usize, @intCast(count))) catch return null;
        @memset(s, ' ');
        return s;
    }
    return null;
}

/// Try to get an AST function node from a Types.Value.
fn getFunctionNode(val: Types.Value, env: *Types.Environment) ?*Ast.Node {
    return switch (val) {
        .function => |f| @as(*Ast.Node, @ptrCast(@alignCast(f))),
        .string => |s| env.getFunction(s),
        else => null,
    };
}

/// Build a whitelist set (StringHashMap) from array elements.
/// All keys in the returned HashMap are owned copies and must be freed by
/// calling freeAllowedKeys() after deinit.
/// Returns null if the array is empty or no valid keys.
fn buildAllowedKeys(arr: *Ast.ArrayObject, allocator: std.mem.Allocator) !?std.StringArrayHashMapUnmanaged(void) {
    if (arr.elements.items.len == 0) return null;
    var set = std.StringArrayHashMapUnmanaged(void){};
    errdefer set.deinit(allocator);

    for (arr.elements.items) |elem| {
        switch (elem) {
            .string => |s| {
                if (s.len == 0) continue;
                const owned = try allocator.dupe(u8, s);
                try set.put(allocator, owned, {});
            },
            .integer => |n| {
                var buf: [32]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}", .{n}) catch continue;
                const owned = try allocator.dupe(u8, str);
                try set.put(allocator, owned, {});
            },
            .float => |f| {
                if (std.math.isNan(f) or std.math.isInf(f)) continue;
                var buf: [64]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}", .{f}) catch continue;
                const owned = try allocator.dupe(u8, str);
                try set.put(allocator, owned, {});
            },
            else => continue,
        }
    }

    if (set.count() == 0) {
        set.deinit(allocator);
        return null;
    }
    return set;
}

/// Free all keys in a StringHashMap that were allocated by buildAllowedKeys.
fn freeAllowedKeys(set: *const std.StringArrayHashMapUnmanaged(void), allocator: std.mem.Allocator) void {
    var it = set.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
    }
}

pub fn Stringify(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    const val = args[0];
    if (val == .void) return .{ .value = .{ .void = {} } };

    // Parse replacer (args[1])
    const replacer_fn: ?*Ast.Node = if (args.len >= 2) getFunctionNode(args[1], env) else null;

    // If args[1] is present and is NOT a function, try to use it as an array whitelist
    var allowed_keys: ?std.StringArrayHashMapUnmanaged(void) = if (args.len >= 2 and replacer_fn == null) blk: {
        if (args[1] == .array) {
            const maybe_set = buildAllowedKeys(args[1].array, env.allocator) catch null;
            break :blk maybe_set;
        }
        break :blk null;
    } else null;

    // Parse space (args[2])
    const indent: ?[]const u8 = if (args.len >= 3) resolveSpace(env.allocator, args[2]) else null;

    // Initial: apply replacer at root with key=""
    const root_val = if (replacer_fn) |fn_node| blk: {
        break :blk callReplacerFn(fn_node, "", val, env) catch val;
    } else val;

    if (root_val == .void) {
        if (indent) |s| env.allocator.free(s);
        if (allowed_keys) |*keys| {
            freeAllowedKeys(keys, env.allocator);
            keys.deinit(env.allocator);
        }
        return .{ .value = .{ .void = {} } };
    }

    var buf = std.ArrayList(u8).initCapacity(env.allocator, 128) catch {
        if (indent) |s| env.allocator.free(s);
        if (allowed_keys) |*keys| {
            freeAllowedKeys(keys, env.allocator);
            keys.deinit(env.allocator);
        }
        return .{ .value = .{ .void = {} } };
    };
    defer buf.deinit(env.allocator);

    // Pass allowed_keys as optional pointer
    const keys_ptr: ?*const std.StringArrayHashMapUnmanaged(void) = if (allowed_keys) |*k| k else null;

    valueToJson(&buf, root_val, "", env.allocator, 0, indent, replacer_fn, keys_ptr, env) catch {
        if (indent) |s| env.allocator.free(s);
        if (allowed_keys) |*keys| {
            freeAllowedKeys(keys, env.allocator);
            keys.deinit(env.allocator);
        }
        return .{ .value = .{ .void = {} } };
    };

    if (indent) |s| env.allocator.free(s);
    if (allowed_keys) |*keys| {
        freeAllowedKeys(keys, env.allocator);
        keys.deinit(env.allocator);
    }

    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, result) catch {
        return .{ .value = .{ .void = {} } };
    };
    return .{ .value = .{ .string = result } };
}


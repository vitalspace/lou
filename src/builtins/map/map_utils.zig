const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

/// Resolves the first argument of a Map method to a Map js_object.
/// Returns null if the argument is missing or not a Map.
pub fn getMap(args: []Types.Value) ?Types.Value {
    if (args.len == 0) return null;
    const obj = args[0];
    if (obj != .js_object) return null;
    const t = obj.js_object.properties.get("@@type") orelse return null;
    if (t != .string or !std.mem.eql(u8, t.string, "Map")) return null;
    return obj;
}

/// Returns the entries array of a Map js_object, or null if missing.
pub fn getEntries(obj: Types.Value) ?*Ast.ArrayObject {
    if (obj.js_object.properties.get("entries")) |v| {
        if (v == .array) return v.array;
    }
    return null;
}

/// Structural equality on key/value pairs. Mirrors the SameValueZero algorithm
/// used by Map and Set for key comparison.
pub fn valuesEqual(a: Types.Value, b: Types.Value) bool {
    return switch (a) {
        .integer => |ai| switch (b) {
            .integer => |bi| ai == bi,
            .float => |bf| @as(f64, @floatFromInt(ai)) == bf,
            else => false,
        },
        .float => |af| switch (b) {
            .float => |bf| af == bf,
            .integer => |bi| af == @as(f64, @floatFromInt(bi)),
            else => false,
        },
        .string => |as_| switch (b) {
            .string => |bs| std.mem.eql(u8, as_, bs),
            else => false,
        },
        .boolean => |ab| switch (b) {
            .boolean => |bb| ab == bb,
            else => false,
        },
        .void => b == .void,
        .null => b == .null,
        else => false,
    };
}

/// Linear search over the entries array. Returns the index of the first pair
/// whose key matches `key`, or null if not found.
pub fn findEntryIndex(entries: *Ast.ArrayObject, key: Types.Value) ?usize {
    for (entries.elements.items, 0..) |pair, i| {
        if (pair == .array) {
            if (pair.array.elements.items.len >= 1) {
                if (valuesEqual(pair.array.elements.items[0], key)) {
                    return i;
                }
            }
        }
    }
    return null;
}

const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn getSet(args: []Types.Value) ?Types.Value {
    if (args.len == 0) return null;
    const obj = args[0];
    if (obj != .js_object) return null;
    const t = obj.js_object.properties.get("@@type") orelse return null;
    if (t != .string or !std.mem.eql(u8, t.string, "Set")) return null;
    return obj;
}

pub fn getValues(obj: Types.Value) ?*Ast.ArrayObject {
    if (obj.js_object.properties.get("values")) |v| {
        if (v == .array) return v.array;
    }
    return null;
}

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
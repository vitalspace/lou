const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Max(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .float = -std.math.inf(f64) } };
    var first = true;
    var max_val: f64 = 0.0;
    for (args) |a| {
        const v: f64 = switch (a) {
            .integer => |i| @as(f64, @floatFromInt(i)),
            .float => |f| f,
            else => std.math.nan(f64),
        };
        if (std.math.isNan(v)) return .{ .value = .{ .float = std.math.nan(f64) } };
        if (first) {
            max_val = v;
            first = false;
        } else if (v > max_val) {
            max_val = v;
        }
    }
    if (first) return .{ .value = .{ .float = -std.math.inf(f64) } };
    return .{ .value = .{ .float = max_val } };
}

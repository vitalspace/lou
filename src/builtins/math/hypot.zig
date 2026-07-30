const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Hypot(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .float = 0.0 } };
    if (args.len == 1) {
        const v = switch (args[0]) {
            .integer => |i| @abs(@as(f64, @floatFromInt(i))),
            .float => |f| @abs(f),
            else => return .{ .value = .{ .float = 0.0 } },
        };
        return .{ .value = .{ .float = v } };
    }
    var sum_sq: f64 = 0.0;
    for (args) |a| {
        const v = switch (a) {
            .integer => |i| @as(f64, @floatFromInt(i)),
            .float => |f| f,
            else => continue,
        };
        sum_sq += v * v;
    }
    return .{ .value = .{ .float = std.math.sqrt(sum_sq) } };
}

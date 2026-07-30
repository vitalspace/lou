const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Atan2(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2) return .{ .value = .{ .float = std.math.nan(f64) } };
    const y = switch (args[0]) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => return .{ .value = .{ .float = std.math.nan(f64) } },
    };
    const x = switch (args[1]) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => return .{ .value = .{ .float = std.math.nan(f64) } },
    };
    return .{ .value = .{ .float = std.math.atan2(y, x) } };
}

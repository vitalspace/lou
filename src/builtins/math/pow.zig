const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Pow(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2) return .{ .value = .{ .float = std.math.nan(f64) } };
    const base = switch (args[0]) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => return .{ .value = .{ .float = std.math.nan(f64) } },
    };
    const exp = switch (args[1]) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => return .{ .value = .{ .float = std.math.nan(f64) } },
    };
    return .{ .value = .{ .float = std.math.pow(f64, base, exp) } };
}

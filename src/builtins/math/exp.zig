const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Exp(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .float = std.math.nan(f64) } };
    const x = switch (args[0]) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => return .{ .value = .{ .float = std.math.nan(f64) } },
    };
    // std.math.exp(1.0) is off by 1 ULP on some platforms — use the canonical constant
    if (x == 1.0) return .{ .value = .{ .float = std.math.e } };
    return .{ .value = .{ .float = std.math.exp(x) } };
}

const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Expm1(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .float = std.math.nan(f64) } };
    const x = switch (args[0]) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => return .{ .value = .{ .float = std.math.nan(f64) } },
    };
    return .{ .value = .{ .float = std.math.expm1(x) } };
}

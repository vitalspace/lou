const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Sign(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .float = std.math.nan(f64) } };
    return switch (args[0]) {
        .integer => |i| {
            if (i > 0) return .{ .value = .{ .integer = 1 } };
            if (i < 0) return .{ .value = .{ .integer = -1 } };
            return .{ .value = .{ .integer = 0 } };
        },
        .float => |f| {
            if (std.math.isNan(f)) return .{ .value = .{ .float = std.math.nan(f64) } };
            if (f > 0.0) return .{ .value = .{ .integer = 1 } };
            if (f < 0.0) return .{ .value = .{ .integer = -1 } };
            return .{ .value = if (f == 0.0) .{ .float = f } else .{ .integer = 0 } };
        },
        else => return .{ .value = .{ .float = std.math.nan(f64) } },
    };
}

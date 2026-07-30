const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Floor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .float = std.math.nan(f64) } };
    return switch (args[0]) {
        .integer => |i| .{ .value = .{ .integer = i } },
        .float => |f| .{ .value = .{ .float = std.math.floor(f) } },
        else => .{ .value = .{ .float = std.math.nan(f64) } },
    };
}

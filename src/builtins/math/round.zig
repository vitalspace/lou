const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Round(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .float = std.math.nan(f64) } };
    return switch (args[0]) {
        .integer => |i| .{ .value = .{ .integer = i } },
        .float => |f| {
            // JS Math.round rounds towards +∞ for .5 tiebreaks,
            // not "half away from zero" like Zig's @round.
            // Use floor(x + 0.5) which gives correct JS behavior.
            return .{ .value = .{ .float = @floor(f + 0.5) } };
        },
        else => .{ .value = .{ .float = std.math.nan(f64) } },
    };
}

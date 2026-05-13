const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Abs(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len != 1) return .{ .value = .{ .float = 0.0 } };
    return switch (args[0]) {
        .float => |f| .{ .value = .{ .float = @abs(f) } },
        .integer => |i| .{ .value = if (i < 0) .{ .integer = -i } else .{ .integer = i } },
        else => .{ .value = .{ .float = 0.0 } },
    };
}
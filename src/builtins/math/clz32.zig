const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Clz32(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .integer = 32 } };
    const x: u32 = switch (args[0]) {
        .integer => |i| @bitCast(@as(i32, @truncate(i))),
        .float => |f| {
            if (std.math.isNan(f)) return .{ .value = .{ .integer = 32 } };
            const i: i64 = @intFromFloat(f);
            const u: u64 = @bitCast(i);
            return .{ .value = .{ .integer = @clz(@as(u32, @truncate(u))) } };
        },
        else => return .{ .value = .{ .integer = 32 } },
    };
    return .{ .value = .{ .integer = @clz(x) } };
}

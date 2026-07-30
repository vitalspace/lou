const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Imul(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2) return .{ .value = .{ .integer = 0 } };
    const a: i32 = switch (args[0]) {
        .integer => |i| @truncate(i),
        .float => |f| @truncate(@as(i64, @intFromFloat(f))),
        else => return .{ .value = .{ .integer = 0 } },
    };
    const b: i32 = switch (args[1]) {
        .integer => |i| @truncate(i),
        .float => |f| @truncate(@as(i64, @intFromFloat(f))),
        else => return .{ .value = .{ .integer = 0 } },
    };
    const result: i32 = a *% b;
    return .{ .value = .{ .integer = @as(i64, result) } };
}

const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

/// Number(value?) — JS `Number()` constructor.
/// Converts a value to a Number (integer/float in our runtime).
/// Special handling: BigInt is converted (with possible precision loss).
pub fn NumberConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) {
        return .{ .value = .{ .integer = 0 } };
    }
    const arg = args[0];
    return switch (arg) {
        .integer => |i| .{ .value = .{ .integer = i } },
        .float => |f| .{ .value = .{ .float = f } },
        .big_int => |big| {
            // Convert BigInt to Number. If value fits in i64, return integer.
            // Otherwise fall back to float. Per JS spec, conversion throws if
            // the value is not a safe integer (we just lose precision here).
            if (big.value.toConst().toInt(i64)) |fit| {
                return .{ .value = .{ .integer = fit } };
            } else |_| {
                const result = big.value.toConst().toFloat(f64, .trunc);
                return .{ .value = .{ .float = result[0] } };
            }
        },
        .boolean => |b| .{ .value = .{ .integer = if (b) 1 else 0 } },
        .string => |s| blk: {
            // Try integer parse first, then float.
            if (std.fmt.parseInt(i64, s, 10)) |i| {
                break :blk .{ .value = .{ .integer = i } };
            } else |_| {}
            if (std.fmt.parseFloat(f64, s)) |f| {
                break :blk .{ .value = .{ .float = f } };
            } else |_| {
                break :blk .{ .value = .{ .float = std.math.nan(f64) } };
            }
        },
        .null => .{ .value = .{ .integer = 0 } },
        .void => .{ .value = .{ .float = std.math.nan(f64) } },
        else => .{ .value = .{ .float = std.math.nan(f64) } },
    };
}

const std = @import("std");
const Types = @import("../../types/types.zig");
const getSet = @import("set_utils.zig").getSet;
const getValues = @import("set_utils.zig").getValues;

pub fn SetToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .string = "[object Set]" } };
    const values = getValues(set_val) orelse return .{ .value = .{ .string = "[object Set]" } };

    var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch {
        return .{ .value = .{ .string = "[object Set]" } };
    };
    defer buf.deinit(env.allocator);

    buf.appendSlice(env.allocator, "Set(") catch {};
    const str = std.fmt.allocPrint(env.allocator, "{d}", .{values.elements.items.len}) catch {
        return .{ .value = .{ .string = "[object Set]" } };
    };
    buf.appendSlice(env.allocator, str) catch {};
    env.allocator.free(str);
    buf.appendSlice(env.allocator, ")") catch {};

    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "[object Set]" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};

    return .{ .value = .{ .string = result } };
}
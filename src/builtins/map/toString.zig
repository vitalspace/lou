const std = @import("std");
const Types = @import("../../types/types.zig");
const map_utils = @import("map_utils.zig");

pub fn MapToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = map_utils.getMap(args) orelse return .{ .value = .{ .string = "[object Map]" } };
    const entries = map_utils.getEntries(map_val) orelse return .{ .value = .{ .string = "[object Map]" } };

    var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch {
        return .{ .value = .{ .string = "[object Map]" } };
    };
    defer buf.deinit(env.allocator);

    buf.appendSlice(env.allocator, "Map(") catch {};
    const str = std.fmt.allocPrint(env.allocator, "{d}", .{entries.elements.items.len}) catch {
        return .{ .value = .{ .string = "[object Map]" } };
    };
    buf.appendSlice(env.allocator, str) catch {};
    env.allocator.free(str);
    buf.appendSlice(env.allocator, ")") catch {};

    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "[object Map]" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};

    return .{ .value = .{ .string = result } };
}

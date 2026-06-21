const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const map_utils = @import("map_utils.zig");

pub fn MapValuesMethod(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = map_utils.getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = map_utils.getEntries(map_val) orelse return .{ .value = .{ .void = {} } };

    const vals_arr = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, vals_arr) catch {
        vals_arr.deinit();
        return .{ .value = .{ .void = {} } };
    };

    for (entries.elements.items) |pair| {
        if (pair == .array and pair.array.elements.items.len >= 2) {
            vals_arr.elements.append(env.allocator, pair.array.elements.items[1]) catch {};
        }
    }

    var iter = Ast.ArrayIterator.initValues(env.allocator, vals_arr) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

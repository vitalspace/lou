const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const map_utils = @import("map_utils.zig");

pub fn MapKeys(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = map_utils.getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = map_utils.getEntries(map_val) orelse return .{ .value = .{ .void = {} } };

    const keys_arr = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, keys_arr) catch {
        keys_arr.deinit();
        return .{ .value = .{ .void = {} } };
    };

    for (entries.elements.items) |pair| {
        if (pair == .array and pair.array.elements.items.len >= 1) {
            keys_arr.elements.append(env.allocator, pair.array.elements.items[0]) catch {};
        }
    }

    var iter = Ast.ArrayIterator.initValues(env.allocator, keys_arr) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

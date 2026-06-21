const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const map_utils = @import("map_utils.zig");

pub fn MapEntries(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const map_val = map_utils.getMap(args) orelse return .{ .value = .{ .void = {} } };
    const entries = map_utils.getEntries(map_val) orelse return .{ .value = .{ .void = {} } };

    var iter = Ast.ArrayIterator.initValues(env.allocator, entries) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}

const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const getSet = @import("set_utils.zig").getSet;
const getValues = @import("set_utils.zig").getValues;

pub fn SetValues(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(set_val) orelse return .{ .value = .{ .void = {} } };

    var iter = Ast.ArrayIterator.initValues(env.allocator, values) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const getSet = @import("set_utils.zig").getSet;
const getValues = @import("set_utils.zig").getValues;

pub fn SetEntries(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const set_val = getSet(args) orelse return .{ .value = .{ .void = {} } };
    const values = getValues(set_val) orelse return .{ .value = .{ .void = {} } };

    const pairs = Ast.ArrayObject.init(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.arrays.append(env.allocator, pairs) catch {
        pairs.deinit();
        return .{ .value = .{ .void = {} } };
    };

    for (values.elements.items) |val| {
        const pair = Ast.ArrayObject.init(env.allocator) catch continue;
        env.arrays.append(env.allocator, pair) catch {
            pair.deinit();
            continue;
        };
        pair.elements.append(env.allocator, val) catch {};
        pair.elements.append(env.allocator, val) catch {};
        pairs.elements.append(env.allocator, .{ .array = pair }) catch {};
    }

    var iter = Ast.ArrayIterator.initValues(env.allocator, pairs) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };

    return .{ .value = .{ .iterator = iter } };
}
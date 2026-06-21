const std = @import("std");
const Types = @import("../../types/types.zig");

/// Resolve a property access on a Set js_object (a `@@type === "Set"` ObjectValue).
/// Returns null if the property is not defined as a data property (the caller
/// will then try method lookup, and finally yield void if that also fails).
///
/// In the ECMAScript spec, the only own data property exposed on a Set instance
/// is `size`. All other `Set.prototype` slots are methods (registered as
/// builtins in `set.zig` via `SET_OBJECT.methods`), not properties.
///
/// Properties defined:
///   - `size` — number of unique values
pub fn resolveProperty(prop_name: []const u8, obj: *const Types.ObjectValue) ?Types.Value {
    if (std.mem.eql(u8, prop_name, "size")) {
        if (obj.properties.get("values")) |vals| {
            if (vals == .array) {
                return .{ .integer = @intCast(vals.array.elements.items.len) };
            }
        }
        return .{ .integer = 0 };
    }
    return null;
}

test "resolveProperty returns value count for size" {
    const allocator = std.testing.allocator;
    var env_ = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env_.deinit();

    const set_val = @import("./set.zig").SetConstructor(&[_]Types.Value{}, &env_).value;
    const obj = set_val.js_object;

    try std.testing.expectEqual(@as(i64, 0), resolveProperty("size", obj).?.integer);

    var a1 = [_]Types.Value{ set_val, .{ .integer = 1 } };
    _ = @import("./set.zig").SetAdd(&a1, &env_);
    var a2 = [_]Types.Value{ set_val, .{ .integer = 2 } };
    _ = @import("./set.zig").SetAdd(&a2, &env_);

    try std.testing.expectEqual(@as(i64, 2), resolveProperty("size", obj).?.integer);
}

test "resolveProperty returns null for unknown properties" {
    const allocator = std.testing.allocator;
    var env_ = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env_.deinit();

    const set_val = @import("./set.zig").SetConstructor(&[_]Types.Value{}, &env_).value;
    try std.testing.expect(resolveProperty("foo", set_val.js_object) == null);
    try std.testing.expect(resolveProperty("constructor", set_val.js_object) == null);
    try std.testing.expect(resolveProperty("add", set_val.js_object) == null);
}

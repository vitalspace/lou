const std = @import("std");
const Types = @import("../../types/types.zig");

/// Resolve a property access on a Map js_object (a `@@type === "Map"` ObjectValue).
/// Returns null if the property is not defined as a data property (the caller
/// will then try method lookup, and finally yield void if that also fails).
///
/// In the ECMAScript spec, the only own data property exposed on a Map instance
/// is `size`. All other `Map.prototype` slots are methods (registered as
/// builtins in `set.zig` via `MAP_OBJECT.methods`), not properties.
///
/// Properties defined:
///   - `size` — number of key-value pairs
pub fn resolveProperty(prop_name: []const u8, obj: *const Types.ObjectValue) ?Types.Value {
    if (std.mem.eql(u8, prop_name, "size")) {
        if (obj.properties.get("entries")) |ents| {
            if (ents == .array) {
                return .{ .integer = @intCast(ents.array.elements.items.len) };
            }
        }
        return .{ .integer = 0 };
    }
    return null;
}

test "resolveProperty returns entry count for size" {
    const allocator = std.testing.allocator;
    var env_ = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env_.deinit();

    const map_val = @import("./constructor.zig").MapConstructor(&[_]Types.Value{}, &env_).value;
    const obj = map_val.js_object;

    try std.testing.expectEqual(@as(i64, 0), resolveProperty("size", obj).?.integer);

    var s1 = [_]Types.Value{ map_val, .{ .integer = 1 }, .{ .string = "a" } };
    _ = @import("./set.zig").MapSet(&s1, &env_);
    var s2 = [_]Types.Value{ map_val, .{ .integer = 2 }, .{ .string = "b" } };
    _ = @import("./set.zig").MapSet(&s2, &env_);

    try std.testing.expectEqual(@as(i64, 2), resolveProperty("size", obj).?.integer);
}

test "resolveProperty returns null for unknown properties" {
    const allocator = std.testing.allocator;
    var env_ = try @import("../../evaluator.zig").Environment.init(allocator, null);
    defer env_.deinit();

    const map_val = @import("./constructor.zig").MapConstructor(&[_]Types.Value{}, &env_).value;
    try std.testing.expect(resolveProperty("foo", map_val.js_object) == null);
    try std.testing.expect(resolveProperty("constructor", map_val.js_object) == null);
    try std.testing.expect(resolveProperty("set", map_val.js_object) == null);
}

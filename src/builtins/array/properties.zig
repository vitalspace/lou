const std = @import("std");
const Types = @import("../../types/types.zig");

/// Resolve a property access on an array value.
/// Returns null if the property is not defined as a data property (the caller
/// will then try method lookup, and finally yield void if that also fails).
///
/// In the ECMAScript spec, the only own data property exposed on an Array
/// instance is `length`. Integer-indexed reads (`arr[0]`) go through the
/// separate `ComputedMemberAccess` / `index_get` path, not through here.
/// All other `Array.prototype` slots are methods (registered as builtins in
/// `src/builtins/array/*.zig` via `ARRAY_OBJECT.methods`), not properties.
///
/// Properties defined:
///   - `length` — number of elements in the array
pub fn resolveProperty(prop_name: []const u8, array: *const Types.ArrayObject) ?Types.Value {
    if (std.mem.eql(u8, prop_name, "length")) {
        return .{ .integer = @intCast(array.elements.items.len) };
    }
    return null;
}

test "resolveProperty returns element count for length" {
    const allocator = std.testing.allocator;
    const arr = try Types.ArrayObject.init(allocator);
    defer arr.deinit();
    try std.testing.expectEqual(@as(i64, 0), resolveProperty("length", arr).?.integer);

    try arr.elements.append(allocator, .{ .integer = 1 });
    try arr.elements.append(allocator, .{ .integer = 2 });
    try arr.elements.append(allocator, .{ .integer = 3 });
    try std.testing.expectEqual(@as(i64, 3), resolveProperty("length", arr).?.integer);
}

test "resolveProperty returns null for unknown properties" {
    const allocator = std.testing.allocator;
    const arr = try Types.ArrayObject.init(allocator);
    defer arr.deinit();
    try std.testing.expect(resolveProperty("foo", arr) == null);
    try std.testing.expect(resolveProperty("constructor", arr) == null);
    try std.testing.expect(resolveProperty("push", arr) == null);
}

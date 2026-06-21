const std = @import("std");
const Types = @import("../../types/types.zig");

/// Resolve a property access on a primitive string value.
/// Returns null if the property is not defined (the caller will yield void).
///
/// In the ECMAScript spec, the only own data property exposed on a string
/// instance is `length`. All other `String.prototype` slots are methods
/// (registered as builtins in `src/builtins/string/*.zig`), not properties,
/// so they are not handled here.
///
/// Properties defined:
///   - `length` — UTF-8 byte length of the string
///
/// Note: in JS, `String.prototype.length` reports UTF-16 code units. We
/// currently report UTF-8 bytes; see `completadas/string-length-property.md`
/// for the rationale and limitations.
pub fn resolveProperty(prop_name: []const u8, str: []const u8) ?Types.Value {
    if (std.mem.eql(u8, prop_name, "length")) {
        return .{ .integer = @intCast(str.len) };
    }
    return null;
}

test "resolveProperty returns byte length for length" {
    try std.testing.expectEqual(@as(i64, 0), resolveProperty("length", "").?.integer);
    try std.testing.expectEqual(@as(i64, 2), resolveProperty("length", "hi").?.integer);
    try std.testing.expectEqual(@as(i64, 5), resolveProperty("length", "hello").?.integer);
}

test "resolveProperty returns null for unknown properties" {
    try std.testing.expect(resolveProperty("constructor", "hi") == null);
    try std.testing.expect(resolveProperty("toUpperCase", "hi") == null);
    try std.testing.expect(resolveProperty("foo", "hi") == null);
}


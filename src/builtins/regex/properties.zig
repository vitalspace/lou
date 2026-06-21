const std = @import("std");
const Types = @import("../../types/types.zig");

/// Resolve a property access on a RegExp instance.
/// Returns null if the property is not defined (the caller will then try
/// method lookup, and finally yield void if that also fails).
///
/// In the ECMAScript spec, RegExp instances expose these own data properties
/// (some read-only, some writable):
///   - `source`     (string, read-only)
///   - `flags`      (string, read-only)
///   - `global`     (bool, read-only)
///   - `ignoreCase` (bool, read-only)
///   - `multiline`  (bool, read-only)
///   - `dotAll`     (bool, read-only)
///   - `unicode`    (bool, read-only)
///   - `sticky`     (bool, read-only)
///   - `hasIndices` (bool, read-only)
///   - `lastIndex`  (integer, writable)
///
/// All other `RegExp.prototype` slots are methods (registered as builtins in
/// `regexp.zig` via `REGEXP_OBJECT.methods`), not properties.
pub fn resolveProperty(prop_name: []const u8, regexp: *const Types.RegExpValue) ?Types.Value {
    if (std.mem.eql(u8, prop_name, "source")) return .{ .string = regexp.pattern };
    if (std.mem.eql(u8, prop_name, "flags")) return .{ .string = regexp.flags_str };
    if (std.mem.eql(u8, prop_name, "global")) return .{ .boolean = regexp.global };
    if (std.mem.eql(u8, prop_name, "ignoreCase")) return .{ .boolean = regexp.ignore_case };
    if (std.mem.eql(u8, prop_name, "multiline")) return .{ .boolean = regexp.multiline };
    if (std.mem.eql(u8, prop_name, "dotAll")) return .{ .boolean = regexp.dot_all };
    if (std.mem.eql(u8, prop_name, "unicode")) return .{ .boolean = regexp.unicode };
    if (std.mem.eql(u8, prop_name, "sticky")) return .{ .boolean = regexp.sticky };
    if (std.mem.eql(u8, prop_name, "hasIndices")) return .{ .boolean = regexp.has_indices };
    if (std.mem.eql(u8, prop_name, "lastIndex")) return .{ .integer = @intCast(regexp.last_index) };
    return null;
}

fn flagsString(re: *const Types.RegExpValue) []const u8 {
    return re.flags_str;
}

/// Outcome of an attempt to assign a writable RegExp property.
pub const SetResult = enum {
    ok,
    read_only,
    invalid_value,
};

/// Assign to a writable RegExp property. Currently only `lastIndex` is writable.
pub fn setProperty(prop_name: []const u8, regexp: *Types.RegExpValue, val: Types.Value) SetResult {
    if (std.mem.eql(u8, prop_name, "lastIndex")) {
        const idx: usize = switch (val) {
            .integer => |i| if (i < 0) return .invalid_value else @intCast(i),
            .float => |f| if (f < 0) return .invalid_value else @intFromFloat(f),
            else => return .invalid_value,
        };
        regexp.setLastIndex(idx);
        return .ok;
    }
    return .read_only;
}

test "resolveProperty source and flags" {
    const allocator = std.testing.allocator;
    const re = try Types.RegExpValue.init(allocator, "hello", "gi");
    defer re.deinit();

    try std.testing.expectEqualStrings("hello", resolveProperty("source", re).?.string);
    try std.testing.expectEqualStrings("gi", resolveProperty("flags", re).?.string);
}

test "resolveProperty boolean flags" {
    const allocator = std.testing.allocator;
    const re = try Types.RegExpValue.init(allocator, "x", "gimsudy");
    defer re.deinit();

    try std.testing.expect(resolveProperty("global", re).?.boolean);
    try std.testing.expect(resolveProperty("ignoreCase", re).?.boolean);
    try std.testing.expect(resolveProperty("multiline", re).?.boolean);
    try std.testing.expect(resolveProperty("dotAll", re).?.boolean);
    try std.testing.expect(resolveProperty("unicode", re).?.boolean);
    try std.testing.expect(resolveProperty("sticky", re).?.boolean);
    try std.testing.expect(resolveProperty("hasIndices", re).?.boolean);
}

test "resolveProperty lastIndex" {
    const allocator = std.testing.allocator;
    const re = try Types.RegExpValue.init(allocator, "x", "g");
    defer re.deinit();

    try std.testing.expectEqual(@as(i64, 0), resolveProperty("lastIndex", re).?.integer);
    re.setLastIndex(42);
    try std.testing.expectEqual(@as(i64, 42), resolveProperty("lastIndex", re).?.integer);
}

test "resolveProperty returns null for unknown" {
    const allocator = std.testing.allocator;
    const re = try Types.RegExpValue.init(allocator, "x", "");
    defer re.deinit();
    try std.testing.expect(resolveProperty("foo", re) == null);
    try std.testing.expect(resolveProperty("constructor", re) == null);
    try std.testing.expect(resolveProperty("exec", re) == null);
}

test "setProperty lastIndex" {
    const allocator = std.testing.allocator;
    const re = try Types.RegExpValue.init(allocator, "x", "g");
    defer re.deinit();

    try std.testing.expectEqual(SetResult.ok, setProperty("lastIndex", re, .{ .integer = 10 }));
    try std.testing.expectEqual(@as(i64, 10), resolveProperty("lastIndex", re).?.integer);

    try std.testing.expectEqual(SetResult.ok, setProperty("lastIndex", re, .{ .float = 3.5 }));
    try std.testing.expectEqual(@as(i64, 3), resolveProperty("lastIndex", re).?.integer);

    try std.testing.expectEqual(SetResult.invalid_value, setProperty("lastIndex", re, .{ .string = "x" }));
    try std.testing.expectEqual(SetResult.read_only, setProperty("source", re, .{ .string = "y" }));
}

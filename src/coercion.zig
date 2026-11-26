const std = @import("std");
const ast = @import("ast.zig");
const Value = ast.Value;

/// ECMAScript `ToNumber` applied to a String (StringNumericLiteral).
///
/// Handles the empty/whitespace string (0), `Infinity`, hex/binary/octal
/// literals and decimal literals; anything else is NaN.
pub fn stringToNumber(s: []const u8) f64 {
    const trimmed = std.mem.trim(u8, s, " \t\n\r\x0b\x0c");
    if (trimmed.len == 0) return 0.0;
    if (std.ascii.eqlIgnoreCase(trimmed, "Infinity")) return std.math.inf(f64);
    if (std.ascii.eqlIgnoreCase(trimmed, "-Infinity")) return -std.math.inf(f64);
    if (std.ascii.eqlIgnoreCase(trimmed, "+Infinity")) return std.math.inf(f64);

    var body = trimmed;
    const signed = body.len > 0 and (body[0] == '+' or body[0] == '-');
    if (signed) body = body[1..];

    // Hex/binary/octal literals are unsigned in ECMAScript: "-0x10" is NaN.
    if (body.len > 2 and body[0] == '0') {
        const radix: u8 = switch (body[1]) {
            'x', 'X' => 16,
            'b', 'B' => 2,
            'o', 'O' => 8,
            else => 0,
        };
        if (radix != 0) {
            if (signed) return std.math.nan(f64);
            const parsed = std.fmt.parseInt(u64, body[2..], radix) catch return std.math.nan(f64);
            return @floatFromInt(parsed);
        }
    }

    return std.fmt.parseFloat(f64, trimmed) catch std.math.nan(f64);
}

/// Append the ECMAScript `ToString` representation of a primitive value.
pub fn appendToString(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    v: Value,
) !void {
    switch (v) {
        .string => |s| try buf.appendSlice(allocator, s),
        .integer => |i| {
            var tmp: [32]u8 = undefined;
            const w = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return error.OutOfMemory;
            try buf.appendSlice(allocator, w);
        },
        .float => |f| try appendNumber(allocator, buf, f),
        .big_int => |b| {
            const digits = b.toString(allocator) catch return error.OutOfMemory;
            defer allocator.free(digits);
            try buf.appendSlice(allocator, digits);
        },
        .boolean => |b| try buf.appendSlice(allocator, if (b) "true" else "false"),
        .null => try buf.appendSlice(allocator, "null"),
        .void, .hole => try buf.appendSlice(allocator, "undefined"),
        .array => |arr| {
            for (arr.elements.items, 0..) |element, i| {
                if (i > 0) try buf.appendSlice(allocator, ",");
                // Array.prototype.join renders null/undefined/holes as empty.
                switch (element) {
                    .null, .void, .hole => {},
                    else => try appendToString(allocator, buf, element),
                }
            }
        },
        .js_object => |obj| {
            if (obj.properties.get("toString")) |ts| {
                if (ts == .string) {
                    try buf.appendSlice(allocator, ts.string);
                    return;
                }
            }
            try buf.appendSlice(allocator, "[object Object]");
        },
        .object, .regexp => try buf.appendSlice(allocator, "[object Object]"),
        else => try buf.appendSlice(allocator, "[object Object]"),
    }
}

fn appendNumber(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), f: f64) !void {
    if (std.math.isNan(f)) {
        try buf.appendSlice(allocator, "NaN");
        return;
    }
    if (std.math.isInf(f)) {
        try buf.appendSlice(allocator, if (f > 0) "Infinity" else "-Infinity");
        return;
    }
    if (f == 0) {
        try buf.appendSlice(allocator, "0");
        return;
    }
    var tmp: [64]u8 = undefined;
    const w = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return error.OutOfMemory;
    var end = w.len;
    if (std.mem.indexOfScalar(u8, tmp[0..end], '.') != null) {
        while (end > 1) {
            const candidate = std.fmt.parseFloat(f64, tmp[0 .. end - 1]) catch break;
            if (candidate != f) break;
            end -= 1;
        }
    }
    try buf.appendSlice(allocator, tmp[0..end]);
}

/// Whether the value is an Object for `==` purposes (needs ToPrimitive).
pub fn isObjectLike(v: Value) bool {
    return switch (v) {
        .array, .js_object, .object, .regexp => true,
        else => false,
    };
}

/// ECMAScript `ToPrimitive(value, default)` for `==` when the value is an
/// Object and the other side is primitive. Arrays go through `join`, plain
/// objects through `toString` when it is a string, else `[object Object]`.
/// Returns an owned string, or null when no conversion applies.
pub fn toPrimitiveString(allocator: std.mem.Allocator, v: Value) ?[]u8 {
    if (!isObjectLike(v)) return null;
    var buf = std.ArrayList(u8).initCapacity(allocator, 16) catch return null;
    errdefer buf.deinit(allocator);
    appendToString(allocator, &buf, v) catch {
        buf.deinit(allocator);
        return null;
    };
    return buf.toOwnedSlice(allocator) catch null;
}

test "stringToNumber - empty and whitespace are zero" {
    try std.testing.expectEqual(@as(f64, 0), stringToNumber(""));
    try std.testing.expectEqual(@as(f64, 0), stringToNumber("  \t"));
}

test "stringToNumber - numeric literals" {
    try std.testing.expectEqual(@as(f64, 42), stringToNumber("42"));
    try std.testing.expectEqual(@as(f64, 16), stringToNumber("0x10"));
    try std.testing.expectEqual(@as(f64, 0.5), stringToNumber(".5"));
    try std.testing.expect(std.math.isNan(stringToNumber("abc")));
}

test "appendToString - array join semantics" {
    const allocator = std.testing.allocator;
    const elements = try allocator.alloc(Value, 2);
    defer allocator.free(elements);
    elements[0] = .{ .integer = 1 };
    elements[1] = .{ .null = {} };
    var arr = try ast.ArrayObject.init(allocator);
    defer arr.deinit();
    arr.elements.appendSlice(allocator, elements) catch {};

    var buf = std.ArrayList(u8).initCapacity(allocator, 8) catch unreachable;
    defer buf.deinit(allocator);
    try appendToString(allocator, &buf, .{ .array = arr });
    try std.testing.expectEqualStrings("1,", buf.items);
}

const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;
const string_utils = @import("string_utils.zig");

/// Strings larger than this codepoint budget are treated as effectively
/// infinite (matches V8's behavior of refusing to allocate an astronomical
/// buffer for `"x".padEnd(1e18)` etc.). Declared as i64 so the same value
/// can be compared directly against `target_length: i64`.
const MAX_PRACTICAL_LEN: i64 = 1 << 30; // ≈ 1 billion codepoints

/// Compute `target_length` from the second argument as an i64, with full
/// handling of NaN / +Inf / -Inf / out-of-range finite floats. The bound
/// check in the caller short-circuits negative and pathologically-large
/// values by returning the original string.
fn targetLengthFromValue(v: Types.Value) i64 {
    return switch (v) {
        .integer => |i| i,
        .float => |f| blk: {
            if (std.math.isNan(f)) break :blk @as(i64, 0);
            if (std.math.isInf(f)) {
                // Sentinel values taken care of by the std.math.cast in the caller.
                break :blk if (f > 0) std.math.maxInt(i64) else std.math.minInt(i64);
            }
            // Clamp finite floats outside i64 range to avoid UB in @intFromFloat.
            if (f >= 9223372036854775808.0) break :blk std.math.maxInt(i64);
            if (f <= -9223372036854775808.0) break :blk std.math.minInt(i64);
            break :blk @as(i64, @intFromFloat(f));
        },
        .void => 0,
        .null => 0,
        .boolean => if (v.boolean) 1 else 0,
        else => 0,
    };
}

pub fn PadEnd(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    const target_length: i64 = if (args.len >= 2) targetLengthFromValue(args[1]) else 0;

    // Single bound check: covers negative targets (incl. -Inf sentinel),
    // i64.max sentinel for +Inf, and pathologically large finite floats.
    if (target_length < 0 or target_length > MAX_PRACTICAL_LEN) {
        return .{ .value = string_utils.dupTracked(env, s) };
    }
    const total_len: usize = @intCast(target_length);

    const s_cp = string_utils.cpCountUsize(s);
    if (total_len <= s_cp) {
        return .{ .value = string_utils.dupTracked(env, s) };
    }

    const pad_string = if (args.len >= 3) switch (args[2]) {
        .string => |ps| ps,
        .void => " ",
        .null => " ",
        else => " ",
    } else " ";

    if (pad_string.len == 0) {
        return .{ .value = string_utils.dupTracked(env, s) };
    }

    const pad_cp = string_utils.cpCountUsize(pad_string);
    const pad_needed = total_len - s_cp;
    var buf = std.ArrayList(u8).initCapacity(env.allocator, total_len) catch {
        return .{ .value = .{ .string = "" } };
    };
    buf.appendSlice(env.allocator, s) catch {};

    var written_cp: usize = 0;
    while (written_cp < pad_needed) {
        const remaining_cp = pad_needed - written_cp;
        const chunk = if (remaining_cp < pad_cp)
            string_utils.cpSlice(pad_string, remaining_cp)
        else
            pad_string;
        buf.appendSlice(env.allocator, chunk) catch {};
        written_cp += string_utils.cpCountUsize(chunk);
    }

    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "padEnd adds dots" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Breaded Mushrooms" }, .{ .integer = 25 }, .{ .string = "." } };
    const result = PadEnd(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("Breaded Mushrooms........", result.value.string);
}

test "padEnd default pad string is space" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Breaded Mushrooms" }, .{ .integer = 25 } };
    const result = PadEnd(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("Breaded Mushrooms        ", result.value.string);
}

test "padEnd targetLength less than string length" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 1 } };
    const result = PadEnd(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padEnd targetLength equal to string length" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 3 } };
    const result = PadEnd(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padEnd with empty pad string returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 10 }, .{ .string = "" } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "padEnd truncates padString from end" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "x" }, .{ .integer = 4 }, .{ .string = "abc" } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("xabc", result.value.string);
}

test "padEnd non-string returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 5 } };
    const result = PadEnd(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "padEnd no args returns empty" {
    const result = PadEnd(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "padEnd multiple repeats of pad string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hi" }, .{ .integer = 8 }, .{ .string = "xy" } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("hixyxyxy", result.value.string);
}

// === Codepoint-aware (UTF-8 multi-byte) cases ===

test "padEnd Unicode Ü pads with one space" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Ü" }, .{ .integer = 2 } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("Ü ", result.value.string);
}

test "padEnd Unicode todos pads" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "café" }, .{ .integer = 6 }, .{ .string = "." } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("café..", result.value.string);
}

test "padEnd multi-byte padString truncates at codepoint boundary" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    // "Ü" is 1 codepoint but 2 bytes; padString "ab" is 2 codepoints.
    // pad_needed = 1 codepoint → truncate "ab" to "a" (1 byte).
    var args = [_]Types.Value{ .{ .string = "Ü" }, .{ .integer = 2 }, .{ .string = "ab" } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("Üa", result.value.string);
}

test "padEnd multi-byte padString repeats fully" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    // "éé" is 2 codepoints = 4 bytes; pad_needed = 3 codepoints → "éé" + first "é" = "ééé"
    var args = [_]Types.Value{ .{ .string = "Ü" }, .{ .integer = 4 }, .{ .string = "éé" } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("Üééé", result.value.string);
}

// === NaN / +Infinity / -Infinity / huge finite ===

test "padEnd NaN targetLength returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .float = std.math.nan(f64) } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padEnd +Infinity targetLength returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .float = std.math.inf(f64) } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padEnd -Infinity targetLength returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .float = -std.math.inf(f64) } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padEnd pathologically large finite targetLength returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    // 1e18 — well within i64 range but absurdly large; matches V8 behavior.
    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .float = 1e18 } };
    const result = PadEnd(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

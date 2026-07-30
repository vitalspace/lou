const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;
const string_utils = @import("string_utils.zig");

/// Strings larger than this codepoint budget are treated as effectively
/// infinite (matches V8's behavior of refusing to allocate an astronomical
/// buffer for `"x".padStart(1e18)` etc.). Declared as i64 so the same value
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
                break :blk if (f > 0) std.math.maxInt(i64) else std.math.minInt(i64);
            }
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

pub fn PadStart(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
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

    buf.appendSlice(env.allocator, s) catch {};

    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "padStart with zeros" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "5" }, .{ .integer = 2 }, .{ .string = "0" } };
    const result = PadStart(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("05", result.value.string);
}

test "padStart with asterisks" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const fullNumber = "2034399002125581";
    const last4 = fullNumber[fullNumber.len - 4 ..];
    var args = [_]Types.Value{ .{ .string = last4 }, .{ .integer = fullNumber.len }, .{ .string = "*" } };
    const result = PadStart(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("************5581", result.value.string);
}

test "padStart default pad string is space" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "x" }, .{ .integer = 4 } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("   x", result.value.string);
}

test "padStart targetLength less than string length" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 1 } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padStart targetLength equal to string length" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .integer = 3 } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padStart with empty pad string returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" }, .{ .integer = 10 }, .{ .string = "" } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "padStart truncates padString from end" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "x" }, .{ .integer = 4 }, .{ .string = "abc" } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("abcx", result.value.string);
}

test "padStart non-string returns empty" {
    var args = [_]Types.Value{ .{ .integer = 42 }, .{ .integer = 5 } };
    const result = PadStart(&args, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "padStart no args returns empty" {
    const result = PadStart(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("", result.value.string);
}

test "padStart multiple repeats of pad string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hi" }, .{ .integer = 8 }, .{ .string = "xy" } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("xyxyxyhi", result.value.string);
}

// === Codepoint-aware (UTF-8 multi-byte) cases ===

test "padStart Unicode Ü pads with one space" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Ü" }, .{ .integer = 2 } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings(" Ü", result.value.string);
}

test "padStart Unicode todos pads" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "café" }, .{ .integer = 6 }, .{ .string = "." } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("..café", result.value.string);
}

test "padStart multi-byte padString truncates at codepoint boundary" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Ü" }, .{ .integer = 2 }, .{ .string = "ab" } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("aÜ", result.value.string);
}

test "padStart multi-byte padString repeats fully" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "Ü" }, .{ .integer = 4 }, .{ .string = "éé" } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("éééÜ", result.value.string);
}

// === NaN / +Infinity / -Infinity / huge finite ===

test "padStart NaN targetLength returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .float = std.math.nan(f64) } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padStart +Infinity targetLength returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .float = std.math.inf(f64) } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padStart -Infinity targetLength returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .float = -std.math.inf(f64) } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

test "padStart pathologically large finite targetLength returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "abc" }, .{ .float = 1e18 } };
    const result = PadStart(&args, &env);
    try testing.expectEqualStrings("abc", result.value.string);
}

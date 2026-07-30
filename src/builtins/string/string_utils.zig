const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn cpCount(s: []const u8) i64 {
    var count: i64 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        i += byte_len;
        count += 1;
    }
    return count;
}

/// Allocate a fresh copy of `s` and register it in `env.owned_strings` so the
/// VM's GC keeps the copy alive until env teardown. Returns `Value.string`
/// with the new allocation, or an empty-string `Value` on allocator failure.
pub fn dupTracked(env: *Types.Environment, s: []const u8) Types.Value {
    const result = env.allocator.dupe(u8, s) catch return .{ .string = "" };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .string = result };
}

/// Same as cpCount but returns usize (for length comparisons and indexing).
/// Uses `std.unicode.utf8CountCodepoints` for valid UTF-8 and falls back to
/// the existing `cpCount` byte-walk (each lead byte = 1 codepoint) for
/// malformed input — reuses rather than duplicates the fallback loop.
pub fn cpCountUsize(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch
        @intCast(cpCount(s));
}

/// Codepoint budget beyond which `target_length` is treated as effectively
/// infinite (matches V8's behavior of refusing to allocate an astronomical
/// buffer for `"x".padEnd(1e18)` etc.). Used by padEnd/padStart.
pub const MAX_PAD_LEN: i64 = 1 << 30; // ≈ 1 billion codepoints

/// Convert the second argument of `target_length` to an i64 with full handling
/// of NaN / ±Infinity / out-of-range finite floats. The bound check in the
/// caller short-circuits negative and pathologically-large values by
/// returning the original string.
pub fn targetLengthFromValue(v: Types.Value) i64 {
    return switch (v) {
        .integer => |i| i,
        .float => |f| blk: {
            if (std.math.isNan(f)) break :blk @as(i64, 0);
            if (std.math.isInf(f)) {
                // +Inf / -Inf sentinels: picked up by the bound check in the caller.
                break :blk if (f > 0) std.math.maxInt(i64) else std.math.minInt(i64);
            }
            // Clamp finite floats outside i64 range to avoid UB in @intFromFloat.
            // 9223372036854775808.0 is 2^63 exactly (representable in f64).
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

/// Truncate a UTF-8 string to at most `max_cp` codepoints, never splitting a
/// multibyte sequence. Returns an empty slice when `max_cp == 0`. Returns `s`
/// unchanged when it has at most `max_cp` codepoints.
pub fn cpSlice(s: []const u8, max_cp: usize) []const u8 {
    if (max_cp == 0) return s[0..0];
    var byte_pos: usize = 0;
    var cp_count: usize = 0;
    while (cp_count < max_cp and byte_pos < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[byte_pos]) catch 1;
        const next_pos = byte_pos + byte_len;
        // Clamp to s.len for malformed UTF-8 (lead byte overshoots past end).
        byte_pos = if (next_pos > s.len) s.len else next_pos;
        cp_count += 1;
    }
    return s[0..byte_pos];
}

pub fn cpToByte(s: []const u8, cp_index: i64) usize {
    if (cp_index <= 0) return 0;
    var remaining = cp_index;
    var i: usize = 0;
    while (i < s.len and remaining > 0) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        i += byte_len;
        remaining -= 1;
    }
    return i;
}

pub fn byteToCp(s: []const u8, byte_offset: usize) i64 {
    var count: i64 = 0;
    var i: usize = 0;
    while (i < s.len and i < byte_offset) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        i += byte_len;
        count += 1;
    }
    return count;
}

pub fn isWhitespaceChar(cp: i32) bool {
    return switch (cp) {
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x00A0,
        0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005,
        0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029,
        0x202F, 0x205F, 0x3000, 0xFEFF => true,
        else => false,
    };
}

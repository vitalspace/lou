const std = @import("std");

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

const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

const DecompEntry = struct { code: u21, base: u21, comb: u21 };

const decomp_table = [_]DecompEntry{
    .{ .code = 0x00C0, .base = 0x0041, .comb = 0x0300 },
    .{ .code = 0x00C1, .base = 0x0041, .comb = 0x0301 },
    .{ .code = 0x00C2, .base = 0x0041, .comb = 0x0302 },
    .{ .code = 0x00C3, .base = 0x0041, .comb = 0x0303 },
    .{ .code = 0x00C4, .base = 0x0041, .comb = 0x0308 },
    .{ .code = 0x00C5, .base = 0x0041, .comb = 0x030A },
    .{ .code = 0x00C7, .base = 0x0043, .comb = 0x0327 },
    .{ .code = 0x00C8, .base = 0x0045, .comb = 0x0300 },
    .{ .code = 0x00C9, .base = 0x0045, .comb = 0x0301 },
    .{ .code = 0x00CA, .base = 0x0045, .comb = 0x0302 },
    .{ .code = 0x00CB, .base = 0x0045, .comb = 0x0308 },
    .{ .code = 0x00CC, .base = 0x0049, .comb = 0x0300 },
    .{ .code = 0x00CD, .base = 0x0049, .comb = 0x0301 },
    .{ .code = 0x00CE, .base = 0x0049, .comb = 0x0302 },
    .{ .code = 0x00CF, .base = 0x0049, .comb = 0x0308 },
    .{ .code = 0x00D1, .base = 0x004E, .comb = 0x0303 },
    .{ .code = 0x00D2, .base = 0x004F, .comb = 0x0300 },
    .{ .code = 0x00D3, .base = 0x004F, .comb = 0x0301 },
    .{ .code = 0x00D4, .base = 0x004F, .comb = 0x0302 },
    .{ .code = 0x00D5, .base = 0x004F, .comb = 0x0303 },
    .{ .code = 0x00D6, .base = 0x004F, .comb = 0x0308 },
    .{ .code = 0x00D9, .base = 0x0055, .comb = 0x0300 },
    .{ .code = 0x00DA, .base = 0x0055, .comb = 0x0301 },
    .{ .code = 0x00DB, .base = 0x0055, .comb = 0x0302 },
    .{ .code = 0x00DC, .base = 0x0055, .comb = 0x0308 },
    .{ .code = 0x00DD, .base = 0x0059, .comb = 0x0301 },
    .{ .code = 0x00E0, .base = 0x0061, .comb = 0x0300 },
    .{ .code = 0x00E1, .base = 0x0061, .comb = 0x0301 },
    .{ .code = 0x00E2, .base = 0x0061, .comb = 0x0302 },
    .{ .code = 0x00E3, .base = 0x0061, .comb = 0x0303 },
    .{ .code = 0x00E4, .base = 0x0061, .comb = 0x0308 },
    .{ .code = 0x00E5, .base = 0x0061, .comb = 0x030A },
    .{ .code = 0x00E7, .base = 0x0063, .comb = 0x0327 },
    .{ .code = 0x00E8, .base = 0x0065, .comb = 0x0300 },
    .{ .code = 0x00E9, .base = 0x0065, .comb = 0x0301 },
    .{ .code = 0x00EA, .base = 0x0065, .comb = 0x0302 },
    .{ .code = 0x00EB, .base = 0x0065, .comb = 0x0308 },
    .{ .code = 0x00EC, .base = 0x0069, .comb = 0x0300 },
    .{ .code = 0x00ED, .base = 0x0069, .comb = 0x0301 },
    .{ .code = 0x00EE, .base = 0x0069, .comb = 0x0302 },
    .{ .code = 0x00EF, .base = 0x0069, .comb = 0x0308 },
    .{ .code = 0x00F1, .base = 0x006E, .comb = 0x0303 },
    .{ .code = 0x00F2, .base = 0x006F, .comb = 0x0300 },
    .{ .code = 0x00F3, .base = 0x006F, .comb = 0x0301 },
    .{ .code = 0x00F4, .base = 0x006F, .comb = 0x0302 },
    .{ .code = 0x00F5, .base = 0x006F, .comb = 0x0303 },
    .{ .code = 0x00F6, .base = 0x006F, .comb = 0x0308 },
    .{ .code = 0x00F9, .base = 0x0075, .comb = 0x0300 },
    .{ .code = 0x00FA, .base = 0x0075, .comb = 0x0301 },
    .{ .code = 0x00FB, .base = 0x0075, .comb = 0x0302 },
    .{ .code = 0x00FC, .base = 0x0075, .comb = 0x0308 },
    .{ .code = 0x00FD, .base = 0x0079, .comb = 0x0301 },
    .{ .code = 0x00FF, .base = 0x0079, .comb = 0x0308 },
};

fn decomposeCp(cp: u21) ?DecompEntry {
    for (decomp_table) |entry| {
        if (entry.code == cp) return entry;
    }
    return null;
}

const CompPair = struct { base: u21, comb: u21, composed: u21 };

const comp_table = [_]CompPair{
    .{ .base = 0x0041, .comb = 0x0300, .composed = 0x00C0 },
    .{ .base = 0x0041, .comb = 0x0301, .composed = 0x00C1 },
    .{ .base = 0x0041, .comb = 0x0302, .composed = 0x00C2 },
    .{ .base = 0x0041, .comb = 0x0303, .composed = 0x00C3 },
    .{ .base = 0x0041, .comb = 0x0308, .composed = 0x00C4 },
    .{ .base = 0x0041, .comb = 0x030A, .composed = 0x00C5 },
    .{ .base = 0x0043, .comb = 0x0327, .composed = 0x00C7 },
    .{ .base = 0x0045, .comb = 0x0300, .composed = 0x00C8 },
    .{ .base = 0x0045, .comb = 0x0301, .composed = 0x00C9 },
    .{ .base = 0x0045, .comb = 0x0302, .composed = 0x00CA },
    .{ .base = 0x0045, .comb = 0x0308, .composed = 0x00CB },
    .{ .base = 0x0049, .comb = 0x0300, .composed = 0x00CC },
    .{ .base = 0x0049, .comb = 0x0301, .composed = 0x00CD },
    .{ .base = 0x0049, .comb = 0x0302, .composed = 0x00CE },
    .{ .base = 0x0049, .comb = 0x0308, .composed = 0x00CF },
    .{ .base = 0x004E, .comb = 0x0303, .composed = 0x00D1 },
    .{ .base = 0x004F, .comb = 0x0300, .composed = 0x00D2 },
    .{ .base = 0x004F, .comb = 0x0301, .composed = 0x00D3 },
    .{ .base = 0x004F, .comb = 0x0302, .composed = 0x00D4 },
    .{ .base = 0x004F, .comb = 0x0303, .composed = 0x00D5 },
    .{ .base = 0x004F, .comb = 0x0308, .composed = 0x00D6 },
    .{ .base = 0x0055, .comb = 0x0300, .composed = 0x00D9 },
    .{ .base = 0x0055, .comb = 0x0301, .composed = 0x00DA },
    .{ .base = 0x0055, .comb = 0x0302, .composed = 0x00DB },
    .{ .base = 0x0055, .comb = 0x0308, .composed = 0x00DC },
    .{ .base = 0x0059, .comb = 0x0301, .composed = 0x00DD },
    .{ .base = 0x0061, .comb = 0x0300, .composed = 0x00E0 },
    .{ .base = 0x0061, .comb = 0x0301, .composed = 0x00E1 },
    .{ .base = 0x0061, .comb = 0x0302, .composed = 0x00E2 },
    .{ .base = 0x0061, .comb = 0x0303, .composed = 0x00E3 },
    .{ .base = 0x0061, .comb = 0x0308, .composed = 0x00E4 },
    .{ .base = 0x0061, .comb = 0x030A, .composed = 0x00E5 },
    .{ .base = 0x0063, .comb = 0x0327, .composed = 0x00E7 },
    .{ .base = 0x0065, .comb = 0x0300, .composed = 0x00E8 },
    .{ .base = 0x0065, .comb = 0x0301, .composed = 0x00E9 },
    .{ .base = 0x0065, .comb = 0x0302, .composed = 0x00EA },
    .{ .base = 0x0065, .comb = 0x0308, .composed = 0x00EB },
    .{ .base = 0x0069, .comb = 0x0300, .composed = 0x00EC },
    .{ .base = 0x0069, .comb = 0x0301, .composed = 0x00ED },
    .{ .base = 0x0069, .comb = 0x0302, .composed = 0x00EE },
    .{ .base = 0x0069, .comb = 0x0308, .composed = 0x00EF },
    .{ .base = 0x006E, .comb = 0x0303, .composed = 0x00F1 },
    .{ .base = 0x006F, .comb = 0x0300, .composed = 0x00F2 },
    .{ .base = 0x006F, .comb = 0x0301, .composed = 0x00F3 },
    .{ .base = 0x006F, .comb = 0x0302, .composed = 0x00F4 },
    .{ .base = 0x006F, .comb = 0x0303, .composed = 0x00F5 },
    .{ .base = 0x006F, .comb = 0x0308, .composed = 0x00F6 },
    .{ .base = 0x0075, .comb = 0x0300, .composed = 0x00F9 },
    .{ .base = 0x0075, .comb = 0x0301, .composed = 0x00FA },
    .{ .base = 0x0075, .comb = 0x0302, .composed = 0x00FB },
    .{ .base = 0x0075, .comb = 0x0308, .composed = 0x00FC },
    .{ .base = 0x0079, .comb = 0x0301, .composed = 0x00FD },
    .{ .base = 0x0079, .comb = 0x0308, .composed = 0x00FF },
};

fn composePair(base: u21, comb: u21) ?u21 {
    for (comp_table) |entry| {
        if (entry.base == base and entry.comb == comb) return entry.composed;
    }
    return null;
}

fn stringToCodepoints(allocator: std.mem.Allocator, s: []const u8) !std.ArrayList(u21) {
    var list = try std.ArrayList(u21).initCapacity(allocator, s.len);
    var i: usize = 0;
    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
            i += 1;
            continue;
        };
        if (i + byte_len > s.len) {
            i += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(s[i .. i + byte_len]) catch {
            i += byte_len;
            continue;
        };
        try list.append(allocator, cp);
        i += byte_len;
    }
    return list;
}

fn codepointsToString(allocator: std.mem.Allocator, cps: []const u21) ![]const u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, cps.len * 3);
    for (cps) |cp| {
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &encoded) catch continue;
        try buf.appendSlice(allocator, encoded[0..len]);
    }
    return buf.toOwnedSlice(allocator);
}

fn isCombiningMark(cp: u21) bool {
    return (cp >= 0x0300 and cp <= 0x036F) or
        (cp >= 0x1DC0 and cp <= 0x1DFF) or
        (cp >= 0x20D0 and cp <= 0x20FF) or
        (cp >= 0xFE20 and cp <= 0xFE2F);
}

fn toNFD(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var cps = try stringToCodepoints(allocator, s);
    defer cps.deinit(allocator);

    var result = try std.ArrayList(u21).initCapacity(allocator, cps.items.len);
    defer result.deinit(allocator);

    for (cps.items) |cp| {
        if (decomposeCp(cp)) |entry| {
            try result.append(allocator, entry.base);
            try result.append(allocator, entry.comb);
        } else {
            try result.append(allocator, cp);
        }
    }

    return codepointsToString(allocator, result.items);
}

fn toNFC(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const nfd = try toNFD(allocator, s);
    defer allocator.free(nfd);

    var cps = try stringToCodepoints(allocator, nfd);
    defer cps.deinit(allocator);

    var result = try std.ArrayList(u21).initCapacity(allocator, cps.items.len);
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < cps.items.len) {
        var base = cps.items[i];
        i += 1;

        var combiners = try std.ArrayList(u21).initCapacity(allocator, 4);
        defer combiners.deinit(allocator);

        while (i < cps.items.len and isCombiningMark(cps.items[i])) {
            try combiners.append(allocator, cps.items[i]);
            i += 1;
        }

        for (combiners.items) |comb| {
            if (composePair(base, comb)) |composed| {
                base = composed;
            } else {
                try result.append(allocator, base);
                base = comb;
            }
        }
        try result.append(allocator, base);
    }

    return codepointsToString(allocator, result.items);
}

fn toNFKD(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var cps = try stringToCodepoints(allocator, s);
    defer cps.deinit(allocator);

    var result = try std.ArrayList(u21).initCapacity(allocator, cps.items.len);
    defer result.deinit(allocator);

    for (cps.items) |cp| {
        if (decomposeCp(cp)) |entry| {
            try result.append(allocator, entry.base);
            try result.append(allocator, entry.comb);
        } else {
            try result.append(allocator, cp);
        }
    }

    return codepointsToString(allocator, result.items);
}

fn toNFKC(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const nfkd = try toNFKD(allocator, s);
    defer allocator.free(nfkd);

    var cps = try stringToCodepoints(allocator, nfkd);
    defer cps.deinit(allocator);

    var result = try std.ArrayList(u21).initCapacity(allocator, cps.items.len);
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < cps.items.len) {
        var base = cps.items[i];
        i += 1;

        var combiners = try std.ArrayList(u21).initCapacity(allocator, 4);
        defer combiners.deinit(allocator);

        while (i < cps.items.len and isCombiningMark(cps.items[i])) {
            try combiners.append(allocator, cps.items[i]);
            i += 1;
        }

        for (combiners.items) |comb| {
            if (composePair(base, comb)) |composed| {
                base = composed;
            } else {
                try result.append(allocator, base);
                base = comb;
            }
        }
        try result.append(allocator, base);
    }

    return codepointsToString(allocator, result.items);
}

pub fn Normalize(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |ss| ss,
        else => return .{ .value = .{ .string = "" } },
    };

    const form = if (args.len >= 2) switch (args[1]) {
        .string => |f| f,
        else => "NFC",
    } else "NFC";

    const result = if (std.mem.eql(u8, form, "NFC")) blk: {
        break :blk toNFC(env.allocator, s) catch {
            return .{ .value = .{ .string = s } };
        };
    } else if (std.mem.eql(u8, form, "NFD")) blk: {
        break :blk toNFD(env.allocator, s) catch {
            return .{ .value = .{ .string = s } };
        };
    } else if (std.mem.eql(u8, form, "NFKC")) blk: {
        break :blk toNFKC(env.allocator, s) catch {
            return .{ .value = .{ .string = s } };
        };
    } else if (std.mem.eql(u8, form, "NFKD")) blk: {
        break :blk toNFKD(env.allocator, s) catch {
            return .{ .value = .{ .string = s } };
        };
    } else {
        return .{ .value = .{ .string = s } };
    };

    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "normalize NFC default" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "\u{0041}\u{006d}\u{00e9}\u{006c}\u{0069}\u{0065}" } };
    const result = Normalize(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
}

test "normalize NFC equivalence" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const name1 = "\u{0041}\u{006d}\u{00e9}\u{006c}\u{0069}\u{0065}";
    const name2 = "\u{0041}\u{006d}\u{0065}\u{0301}\u{006c}\u{0069}\u{0065}";

    var args1 = [_]Types.Value{ .{ .string = name1 }, .{ .string = "NFC" } };
    var args2 = [_]Types.Value{ .{ .string = name2 }, .{ .string = "NFC" } };

    const r1 = Normalize(&args1, &env);
    const r2 = Normalize(&args2, &env);

    try testing.expectEqualStrings(r1.value.string, r2.value.string);
}

test "normalize NFD decomposition" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const args = [_]Types.Value{ .{ .string = "\u{00e9}" }, .{ .string = "NFD" } };
    const result = Normalize(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("\u{0065}\u{0301}", result.value.string);
}

test "normalize NFC re-composition" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const args = [_]Types.Value{ .{ .string = "\u{0065}\u{0301}" }, .{ .string = "NFC" } };
    const result = Normalize(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("\u{00e9}", result.value.string);
}

test "normalize no args returns empty string" {
    const result = Normalize(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("", result.value.string);
}

test "normalize non-string returns empty string" {
    const result = Normalize(&[_]Types.Value{ .{ .integer = 42 } }, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("", result.value.string);
}

test "normalize unknown form returns original" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const args = [_]Types.Value{ .{ .string = "hello" }, .{ .string = "UNKNOWN" } };
    const result = Normalize(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("hello", result.value.string);
}

test "normalize NFKC returns string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const args = [_]Types.Value{ .{ .string = "\u{00e9}" }, .{ .string = "NFKC" } };
    const result = Normalize(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
}

test "normalize NFKD returns string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const args = [_]Types.Value{ .{ .string = "\u{00e9}" }, .{ .string = "NFKD" } };
    const result = Normalize(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("\u{0065}\u{0301}", result.value.string);
}

test "normalize roundtrip NFC then NFC" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const args1 = [_]Types.Value{ .{ .string = "\u{0041}\u{0301}" }, .{ .string = "NFC" } };
    const r1 = Normalize(&args1, &env);
    const args2 = [_]Types.Value{ .{ .string = r1.value.string }, .{ .string = "NFC" } };
    const r2 = Normalize(&args2, &env);
    try testing.expectEqualStrings(r1.value.string, r2.value.string);
}

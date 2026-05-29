const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn isTurkishLocale(locale: []const u8) bool {
    if (locale.len < 2) return false;
    const prefix = locale[0..2];
    return std.mem.eql(u8, prefix, "tr") or std.mem.eql(u8, prefix, "az");
}

pub fn ToLocaleUpper(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .string = "" } };
    const s = switch (args[0]) {
        .string => |s| s,
        else => return .{ .value = .{ .void = {} } },
    };

    var turkish = false;
    if (args.len >= 2) {
        switch (args[1]) {
            .string => |loc| turkish = isTurkishLocale(loc),
            else => {},
        }
    }

    var buf = std.ArrayList(u8).initCapacity(env.allocator, s.len) catch {
        return .{ .value = .{ .void = {} } };
    };
    var i: usize = 0;
    while (i < s.len) {
        const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
            buf.append(env.allocator, s[i]) catch {};
            i += 1;
            continue;
        };
        const cp = std.unicode.utf8Decode(s[i .. i + byte_len]) catch {
            buf.appendSlice(env.allocator, s[i .. i + byte_len]) catch {};
            i += byte_len;
            continue;
        };
        const upper: u21 = if (turkish and cp == 'i') 0x0130 else switch (@as(u21, @intCast(cp))) {
            'a'...'z' => cp - 32,
            else => cp,
        };
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(upper, &encoded) catch unreachable;
        buf.appendSlice(env.allocator, encoded[0..len]) catch {};
        i += byte_len;
    }
    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

const testing = std.testing;

test "toLocaleUpperCase converts lowercase" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "hello" } };
    const result = ToLocaleUpper(&args, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("HELLO", result.value.string);
}

test "toLocaleUpperCase no change for already uppercase" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "ISTANBUL" } };
    const result = ToLocaleUpper(&args, &env);
    try testing.expectEqualStrings("ISTANBUL", result.value.string);
}

test "toLocaleUpperCase with locales parameter" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "istanbul" }, .{ .string = "en-US" } };
    const result = ToLocaleUpper(&args, &env);
    try testing.expect(result == .value);
    try testing.expectEqualStrings("ISTANBUL", result.value.string);
}

test "toLocaleUpperCase Turkish locale" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "i" }, .{ .string = "tr" } };
    const result = ToLocaleUpper(&args, &env);
    try testing.expectEqualStrings("\u{130}", result.value.string);
}

test "toLocaleUpperCase empty string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{ .{ .string = "" } };
    const result = ToLocaleUpper(&args, &env);
    try testing.expectEqualStrings("", result.value.string);
}

test "toLocaleUpperCase non-string returns void" {
    var args = [_]Types.Value{ .{ .integer = 42 } };
    const result = ToLocaleUpper(&args, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .void);
}

test "toLocaleUpperCase no args returns empty string" {
    const result = ToLocaleUpper(&[_]Types.Value{}, undefined);
    try testing.expect(result == .value);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("", result.value.string);
}

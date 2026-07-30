const std = @import("std");
const Types = @import("../types/types.zig");

/// Characters that encodeURI does NOT encode.
fn isUriUnescaped(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9' => true,
        ';', ',', '/', '?', ':', '@', '&', '=', '+', '$' => true,
        '-', '_', '.', '!', '~', '*', '\'', '(', ')', '#' => true,
        else => false,
    };
}

/// Characters that encodeURIComponent does NOT encode.
fn isUriComponentUnescaped(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9' => true,
        '-', '_', '.', '!', '~', '*', '\'', '(', ')' => true,
        else => false,
    };
}

const HexChars = "0123456789ABCDEF";

/// Percent-encode a string. `checkFn` decides whether a byte is already safe.
fn percentEncode(allocator: std.mem.Allocator, input: []const u8, checkFn: fn (u8) bool) ![]u8 {
    // First pass: count how many bytes need encoding to allocate exact size.
    var extra: usize = 0;
    for (input) |b| {
        if (!checkFn(b)) extra += 2; // each encoded byte becomes %XX (2 extra chars)
    }
    const out = try allocator.alloc(u8, input.len + extra);
    var pos: usize = 0;
    for (input) |b| {
        if (checkFn(b)) {
            out[pos] = b;
            pos += 1;
        } else {
            out[pos] = '%';
            out[pos + 1] = HexChars[b >> 4];
            out[pos + 2] = HexChars[b & 0xF];
            pos += 3;
        }
    }
    return out;
}

/// Decode percent-encoded string. Returns error.MalformedURI if there's an
/// invalid %-sequence (e.g. %G0, %0, or unpaired surrogate bytes that can't
/// form valid UTF-8).
fn percentDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var buf = std.ArrayList(u8).initCapacity(allocator, input.len) catch return error.OutOfMemory;
    errdefer buf.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        if (input[i] == '%') {
            if (i + 2 >= input.len) {
                // Premature end — malformed URI (errdefer handles cleanup)
                return error.MalformedURI;
            }
            const hi = hexVal(input[i + 1]);
            const lo = hexVal(input[i + 2]);
            if (hi == null or lo == null) {
                // Invalid hex chars (errdefer handles cleanup)
                return error.MalformedURI;
            }
            try buf.append(allocator, hi.? << 4 | lo.?);
            i += 2;
        } else {
            try buf.append(allocator, input[i]);
        }
    }

    // Validate the resulting bytes are valid UTF-8.
    const bytes = try buf.toOwnedSlice(allocator);
    if (!std.unicode.utf8ValidateSlice(bytes)) {
        allocator.free(bytes);
        return error.MalformedURI;
    }
    return bytes;
}

fn hexVal(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'F' => c - 'A' + 10,
        'a'...'f' => c - 'a' + 10,
        else => null,
    };
}

fn throwUriError(env: *Types.Environment, msg_text: []const u8) void {
    const obj = Types.ObjectValue.init(env.allocator) catch {
        env.throw_hit = true;
        env.throw_value = .{ .string = "URIError: URI malformed" };
        return;
    };
    const name = env.allocator.dupe(u8, "URIError") catch {
        obj.deinit();
        return;
    };
    obj.properties.put("name", .{ .string = name }) catch {};
    const msg = env.allocator.dupe(u8, msg_text) catch {
        env.allocator.free(name);
        obj.deinit();
        return;
    };
    obj.properties.put("message", .{ .string = msg }) catch {};
    // Append to env tracking lists only after all allocations succeed.
    env.objects.append(env.allocator, obj) catch {};
    env.owned_strings.append(env.allocator, name) catch {};
    env.owned_strings.append(env.allocator, msg) catch {};
    env.throw_hit = true;
    env.throw_value = .{ .js_object = obj };
}

/// encodeURI(str) — encodes a complete URI, preserving characters that have
/// special meaning in URIs: `; , / ? : @ & = + $ - _ . ! ~ * ' ( ) #`
/// Alphanumerics are also left intact. All other characters (including
/// non-ASCII Unicode bytes) are percent-encoded.
pub fn encodeUri(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .string = "undefined" } };
    const input = switch (args[0]) {
        .string => |s| s,
        .void => return .{ .value = .{ .string = "undefined" } },
        .null => return .{ .value = .{ .string = "null" } },
        .boolean => |b| return .{ .value = .{ .string = if (b) "true" else "false" } },
        else => |v| {
            // Use toString coercion: for numbers, bigints, etc.
            _ = v;
            return .{ .value = .{ .string = "undefined" } };
        },
    };
    const result = percentEncode(env.allocator, input, isUriUnescaped) catch {
        return .{ .value = .{ .string = input } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

/// decodeURI(str) — decodes a URI previously encoded with encodeURI.
/// Throws URIError for malformed %-sequences.
pub fn decodeUri(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .string = "undefined" } };
    const input = switch (args[0]) {
        .string => |s| s,
        .void => return .{ .value = .{ .string = "undefined" } },
        .null => return .{ .value = .{ .string = "null" } },
        else => return .{ .value = .{ .string = "undefined" } },
    };
    const result = percentDecode(env.allocator, input) catch {
        throwUriError(env, "URI malformed");
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

/// encodeURIComponent(str) — encodes a URI component, escaping ALL characters
/// except `A-Z a-z 0-9 - _ . ! ~ * ' ( )`. This is the stricter variant
/// suitable for query string values.
pub fn encodeUriComponent(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .string = "undefined" } };
    const input = switch (args[0]) {
        .string => |s| s,
        .void => return .{ .value = .{ .string = "undefined" } },
        .null => return .{ .value = .{ .string = "null" } },
        .boolean => |b| return .{ .value = .{ .string = if (b) "true" else "false" } },
        else => return .{ .value = .{ .string = "undefined" } },
    };
    const result = percentEncode(env.allocator, input, isUriComponentUnescaped) catch {
        return .{ .value = .{ .string = input } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

/// decodeURIComponent(str) — decodes a URI component previously encoded with
/// encodeURIComponent. Throws URIError for malformed %-sequences.
pub fn decodeUriComponent(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .string = "undefined" } };
    const input = switch (args[0]) {
        .string => |s| s,
        .void => return .{ .value = .{ .string = "undefined" } },
        .null => return .{ .value = .{ .string = "null" } },
        else => return .{ .value = .{ .string = "undefined" } },
    };
    const result = percentDecode(env.allocator, input) catch {
        throwUriError(env, "URI malformed");
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

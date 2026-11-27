const std = @import("std");
const Types = @import("../../types/types.zig");
const ToUpper = @import("toUpperCase.zig").ToUpper;
const ToLower = @import("toLowerCase.zig").ToLower;
const ToLocaleUpper = @import("toLocaleUpperCase.zig").ToLocaleUpper;
const ToLocaleLower = @import("toLocaleLowerCase.zig").ToLocaleLower;
const ToString = @import("toString.zig").ToString;
const ToWellFormed = @import("toWellFormed.zig").ToWellFormed;
const Trim = @import("trim.zig").Trim;
const TrimEnd = @import("trimEnd.zig").TrimEnd;
const TrimStart = @import("trimStart.zig").TrimStart;
const ValueOf = @import("valueOf.zig").ValueOf;
const Substr = @import("substr.zig").Substr;
const Substring = @import("substring.zig").Substring;
const At = @import("at.zig").At;
const CharAt = @import("charAt.zig").CharAt;
const CharCodeAt = @import("charCodeAt.zig").CharCodeAt;
const CodePointAt = @import("codePointAt.zig").CodePointAt;
const Concat = @import("concat.zig").Concat;
const EndsWith = @import("endsWith.zig").EndsWith;
const Includes = @import("includes.zig").Includes;
const IndexOf = @import("indexOf.zig").IndexOf;
const IsWellFormed = @import("isWellFormed.zig").IsWellFormed;
const LastIndexOf = @import("lastIndexOf.zig").LastIndexOf;
const LocaleCompare = @import("localeCompare.zig").LocaleCompare;
const Match = @import("match.zig").Match;
const MatchAll = @import("matchAll.zig").MatchAll;
const Normalize = @import("normalize.zig").Normalize;
const PadEnd = @import("padEnd.zig").PadEnd;
const PadStart = @import("padStart.zig").PadStart;
const Repeat = @import("repeat.zig").Repeat;
const Replace = @import("replace.zig").Replace;
const ReplaceAll = @import("replaceAll.zig").ReplaceAll;
const Search = @import("search.zig").Search;
const Slice = @import("slice.zig").Slice;
const Split = @import("split.zig").Split;
const StartsWith = @import("startsWith.zig").StartsWith;

pub fn StringConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) {
        const s = env.allocator.dupe(u8, "") catch return .{ .value = .{ .void = {} } };
        env.owned_strings.append(env.allocator, s) catch {};
        return .{ .value = .{ .string = s } };
    }
    return .{ .value = valueToString(env, args[0]) };
}

/// Convert a Value to its JS string representation (ES ToString).
/// BigInt is rendered without the trailing 'n' (unlike console.log / valToStr).
fn valueToString(env: *Types.Environment, v: Types.Value) Types.Value {
    switch (v) {
        .string => |s| return .{ .string = s },
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const w = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return .{ .void = {} };
            const s = env.allocator.dupe(u8, buf[0..w.len]) catch return .{ .void = {} };
            env.owned_strings.append(env.allocator, s) catch {};
            return .{ .string = s };
        },
        .float => |f| {
            if (std.math.isNan(f)) return .{ .string = "NaN" };
            if (std.math.isInf(f)) return .{ .string = if (f > 0) "Infinity" else "-Infinity" };
            var buf: [64]u8 = undefined;
            const w = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return .{ .void = {} };
            const s = env.allocator.dupe(u8, buf[0..w.len]) catch return .{ .void = {} };
            env.owned_strings.append(env.allocator, s) catch {};
            return .{ .string = s };
        },
        .big_int => |b| {
            // BigInt without the trailing 'n' (unlike console.log / valToStr)
            const digits = b.toString(env.allocator) catch return .{ .void = {} };
            defer env.allocator.free(digits);
            const s = env.allocator.dupe(u8, digits) catch return .{ .void = {} };
            env.owned_strings.append(env.allocator, s) catch {};
            return .{ .string = s };
        },
        .boolean => |b| return .{ .string = if (b) "true" else "false" },
        .void, .hole => return .{ .string = "undefined" },
        .null => return .{ .string = "null" },
        .symbol => |sym| {
            if (sym.description.len > 0) {
                const prefix = "Symbol(";
                const suffix = ")";
                const total = prefix.len + sym.description.len + suffix.len;
                const buf = env.allocator.alloc(u8, total) catch return .{ .void = {} };
                @memcpy(buf[0..prefix.len], prefix);
                @memcpy(buf[prefix.len..][0..sym.description.len], sym.description);
                @memcpy(buf[prefix.len + sym.description.len ..][0..suffix.len], suffix);
                env.owned_strings.append(env.allocator, buf) catch {};
                return .{ .string = buf };
            }
            return .{ .string = "Symbol()" };
        },
        .function, .closure => return .{ .string = "function" },
        .generator => return .{ .string = "function" },
        else => return .{ .string = "[object]" },
    }
}


test "String constructor coerces primitives" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    var int_args = [_]Types.Value{.{ .integer = 42 }};
    const int_res = StringConstructor(&int_args, &env);
    try testing.expectEqualStrings("42", int_res.value.string);

    var null_args = [_]Types.Value{.{ .null = {} }};
    const null_res = StringConstructor(&null_args, &env);
    try testing.expectEqualStrings("null", null_res.value.string);
}

test "String constructor renders symbols without throwing" {
    var env = try Types.Environment.init(testing.allocator, null);
    defer env.deinit();

    const sym = try Types.SymbolValue.init(testing.allocator, 1, "x");
    defer sym.deinit();
    var args = [_]Types.Value{.{ .symbol = sym }};
    const res = StringConstructor(&args, &env);
    try testing.expectEqualStrings("Symbol(x)", res.value.string);
}
pub const STRING_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "toUpperCase", .func = ToUpper },
    .{ .name = "toLocaleUpperCase", .func = ToLocaleUpper },
    .{ .name = "toLocaleLowerCase", .func = ToLocaleLower },
    .{ .name = "toLowerCase", .func = ToLower },
    .{ .name = "toString", .func = ToString },
    .{ .name = "toWellFormed", .func = ToWellFormed },
    .{ .name = "trim", .func = Trim },
    .{ .name = "trimEnd", .func = TrimEnd },
    .{ .name = "trimStart", .func = TrimStart },
    .{ .name = "valueOf", .func = ValueOf },
    .{ .name = "substr", .func = Substr },
    .{ .name = "substring", .func = Substring },
    .{ .name = "at", .func = At },
    .{ .name = "charAt", .func = CharAt },
    .{ .name = "charCodeAt", .func = CharCodeAt },
    .{ .name = "codePointAt", .func = CodePointAt },
    .{ .name = "concat", .func = Concat },
    .{ .name = "endsWith", .func = EndsWith },
    .{ .name = "includes", .func = Includes },
    .{ .name = "indexOf", .func = IndexOf },
    .{ .name = "isWellFormed", .func = IsWellFormed },
    .{ .name = "lastIndexOf", .func = LastIndexOf },
    .{ .name = "localeCompare", .func = LocaleCompare },
    .{ .name = "match", .func = Match },
    .{ .name = "matchAll", .func = MatchAll },
    .{ .name = "normalize", .func = Normalize },
    .{ .name = "padEnd", .func = PadEnd },
    .{ .name = "padStart", .func = PadStart },
    .{ .name = "repeat", .func = Repeat },
    .{ .name = "replace", .func = Replace },
    .{ .name = "replaceAll", .func = ReplaceAll },
    .{ .name = "search", .func = Search },
    .{ .name = "slice", .func = Slice },
    .{ .name = "split", .func = Split },
    .{ .name = "startsWith", .func = StartsWith },
};

const testing = std.testing;

pub const STRING_OBJECT = Types.BuiltinObjectImpl{
    .name = "String",
    .methods = &STRING_METHODS,
};

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

pub const STRING_OBJECT = Types.BuiltinObjectImpl{
    .name = "String",
    .methods = &STRING_METHODS,
};

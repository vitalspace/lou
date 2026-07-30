const Types = @import("../../types/types.zig");
const Push = @import("push.zig").Push;
const Pop = @import("pop.zig").Pop;
const At = @import("at.zig").At;
const Concat = @import("concat.zig").Concat;
const CopyWithin = @import("copyWithin.zig").CopyWithin;
const Entries = @import("entries.zig").Entries;
const Every = @import("every.zig").Every;
const Fill = @import("fill.zig").Fill;
const Filter = @import("filter.zig").Filter;
const Find = @import("find.zig").Find;
const FindIndex = @import("findIndex.zig").FindIndex;
const FindLast = @import("findLast.zig").FindLast;
const FindLastIndex = @import("findLastIndex.zig").FindLastIndex;
const Flat = @import("flat.zig").Flat;
const FlatMap = @import("flatMap.zig").FlatMap;
const ForEach = @import("forEach.zig").ForEach;
const From = @import("from.zig").From;
const Includes = @import("includes.zig").Includes;
const IndexOf = @import("indexOf.zig").IndexOf;
const IsArray = @import("isArray.zig").IsArray;
const Join = @import("join.zig").Join;
const Keys = @import("keys.zig").Keys;
const LastIndexOf = @import("lastIndexOf.zig").LastIndexOf;
const Map = @import("map.zig").Map;
const Reduce = @import("reduce.zig").Reduce;
const ReduceRight = @import("reduceRight.zig").ReduceRight;
const Reverse = @import("reverse.zig").Reverse;
const Shift = @import("shift.zig").Shift;
const Slice = @import("slice.zig").Slice;
const Some = @import("some.zig").Some;
const Sort = @import("sort.zig").Sort;
const Splice = @import("splice.zig").Splice;
const ToReversed = @import("toReversed.zig").ToReversed;
const ToSorted = @import("toSorted.zig").ToSorted;
const ToSpliced = @import("toSpliced.zig").ToSpliced;
const ToString = @import("toString.zig").ToString;
const Unshift = @import("unshift.zig").Unshift;
const Values = @import("values.zig").Values;
const With = @import("with.zig").With;

pub const ARRAY_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "push", .func = Push },
    .{ .name = "pop", .func = Pop },
    .{ .name = "at", .func = At },
    .{ .name = "concat", .func = Concat },
    .{ .name = "copyWithin", .func = CopyWithin },
    .{ .name = "entries", .func = Entries },
    .{ .name = "every", .func = Every },
    .{ .name = "fill", .func = Fill },
    .{ .name = "filter", .func = Filter },
    .{ .name = "find", .func = Find },
    .{ .name = "findIndex", .func = FindIndex },
    .{ .name = "findLast", .func = FindLast },
    .{ .name = "findLastIndex", .func = FindLastIndex },
    .{ .name = "flat", .func = Flat },
    .{ .name = "flatMap", .func = FlatMap },
    .{ .name = "forEach", .func = ForEach },
    .{ .name = "from", .func = From },
    .{ .name = "includes", .func = Includes },
    .{ .name = "indexOf", .func = IndexOf },
    .{ .name = "isArray", .func = IsArray },
    .{ .name = "join", .func = Join },
    .{ .name = "keys", .func = Keys },
    .{ .name = "lastIndexOf", .func = LastIndexOf },
    .{ .name = "map", .func = Map },
    .{ .name = "reduce", .func = Reduce },
    .{ .name = "reduceRight", .func = ReduceRight },
    .{ .name = "reverse", .func = Reverse },
    .{ .name = "shift", .func = Shift },
    .{ .name = "slice", .func = Slice },
    .{ .name = "some", .func = Some },
    .{ .name = "sort", .func = Sort },
    .{ .name = "splice", .func = Splice },
    .{ .name = "toReversed", .func = ToReversed },
    .{ .name = "toSorted", .func = ToSorted },
    .{ .name = "toSpliced", .func = ToSpliced },
    .{ .name = "toString", .func = ToString },
    .{ .name = "unshift", .func = Unshift },
    .{ .name = "values", .func = Values },
    .{ .name = "with", .func = With },
};

pub const ARRAY_OBJECT = Types.BuiltinObjectImpl{
    .name = "Array",
    .methods = &ARRAY_METHODS,
};

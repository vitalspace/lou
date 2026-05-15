const Types = @import("../../types/types.zig");
const Length = @import("length.zig").Length;
const Push = @import("push.zig").Push;
const Pop = @import("pop.zig").Pop;
const At = @import("at.zig").At;
const Concat = @import("concat.zig").Concat;
const CopyWithin = @import("copyWithin.zig").CopyWithin;
const Entries = @import("entries.zig").Entries;
const Every = @import("every.zig").Every;

const ARRAY_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "length", .func = Length },
    .{ .name = "push", .func = Push },
    .{ .name = "pop", .func = Pop },
    .{ .name = "at", .func = At },
    .{ .name = "concat", .func = Concat },
    .{ .name = "copyWithin", .func = CopyWithin },
    .{ .name = "entries", .func = Entries },
    .{ .name = "every", .func = Every },
};

pub const ARRAY_OBJECT = Types.BuiltinObjectImpl{
    .name = "Array",
    .methods = &ARRAY_METHODS,
};

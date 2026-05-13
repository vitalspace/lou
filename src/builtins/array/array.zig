const Types = @import("../../types/types.zig");
const Length = @import("length.zig").Length;
const Push = @import("push.zig").Push;
const Pop = @import("pop.zig").Pop;

const ARRAY_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "length", .func = Length },
    .{ .name = "push", .func = Push },
    .{ .name = "pop", .func = Pop },
};

pub const ARRAY_OBJECT = Types.BuiltinObjectImpl{
    .name = "Array",
    .methods = &ARRAY_METHODS,
};

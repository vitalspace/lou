const Types = @import("../../types/types.zig");
const Abs = @import("abs.zig").Abs;

const MATH_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "abs", .func = Abs },
};

pub const MATH_OBJECT = Types.BuiltinObjectImpl{
    .name = "Math",
    .methods = &MATH_METHODS,
};
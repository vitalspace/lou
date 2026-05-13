const Types = @import("../types/types.zig");
const CONSOLE_OBJECT = @import("./console/console.zig").CONSOLE_OBJECT;
const ARRAY_OBJECT = @import("./array/array.zig").ARRAY_OBJECT;
const MATH_OBJECT = @import("./math/math.zig").MATH_OBJECT;

pub const BUILTIN_OBJECTS = [_]*const Types.BuiltinObjectImpl{
    &CONSOLE_OBJECT,
    &ARRAY_OBJECT,
    &MATH_OBJECT,
};
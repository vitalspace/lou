const Types = @import("../types/types.zig");
const CONSOLE_OBJECT = @import("./console/console.zig").CONSOLE_OBJECT;
const ARRAY_OBJECT = @import("./array/array.zig").ARRAY_OBJECT;
const MATH_OBJECT = @import("./math/math.zig").MATH_OBJECT;
const STRING_OBJECT = @import("./string/string.zig").STRING_OBJECT;
const SET_OBJECT = @import("./set/set.zig").SET_OBJECT;
const MAP_OBJECT = @import("./map/map.zig").MAP_OBJECT;
const OBJECT_OBJECT = @import("./object/object.zig").OBJECT_OBJECT;

pub const BUILTIN_OBJECTS = [_]*const Types.BuiltinObjectImpl{
    &CONSOLE_OBJECT,
    &ARRAY_OBJECT,
    &MATH_OBJECT,
    &STRING_OBJECT,
    &SET_OBJECT,
    &MAP_OBJECT,
    &OBJECT_OBJECT,
};

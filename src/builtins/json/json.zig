const Types = @import("../../types/types.zig");
const Stringify = @import("stringify.zig").Stringify;

const JSON_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "stringify", .func = Stringify },
};

pub const JSON_OBJECT = Types.BuiltinObjectImpl{
    .name = "JSON",
    .methods = &JSON_METHODS,
};

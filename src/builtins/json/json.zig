const Types = @import("../../types/types.zig");
const Stringify = @import("stringify.zig").Stringify;
const Parse = @import("parse.zig").Parse;

const JSON_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "stringify", .func = Stringify },
    .{ .name = "parse", .func = Parse },
};

pub const JSON_OBJECT = Types.BuiltinObjectImpl{
    .name = "JSON",
    .methods = &JSON_METHODS,
};

const Types = @import("../../types/types.zig");
const Keys = @import("keys.zig").Keys;
const Assign = @import("assign.zig").Assign;
const Entries = @import("entries.zig").Entries;
const Values = @import("values.zig").Values;
const HasOwn = @import("hasOwn.zig").HasOwn;
const Create = @import("create.zig").Create;
const GroupBy = @import("groupBy.zig").GroupBy;

const OBJECT_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "keys", .func = Keys },
    .{ .name = "assign", .func = Assign },
    .{ .name = "entries", .func = Entries },
    .{ .name = "values", .func = Values },
    .{ .name = "hasOwn", .func = HasOwn },
    .{ .name = "create", .func = Create },
    .{ .name = "groupBy", .func = GroupBy },
};

pub const OBJECT_OBJECT = Types.BuiltinObjectImpl{
    .name = "Object",
    .methods = &OBJECT_METHODS,
};
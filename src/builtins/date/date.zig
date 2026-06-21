const Types = @import("../../types/types.zig");
const Methods = @import("methods.zig");
const Static = @import("static.zig");

/// Instance methods on `Date.prototype`, called via MethodCall as
/// `someDate.method(...)` with `this` prepended as first argument.
pub const DATE_INSTANCE_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "getTime", .func = Methods.DateGetTime },
    .{ .name = "valueOf", .func = Methods.DateValueOf },
    .{ .name = "getFullYear", .func = Methods.DateGetFullYear },
    .{ .name = "getMonth", .func = Methods.DateGetMonth },
    .{ .name = "getDate", .func = Methods.DateGetDate },
    .{ .name = "getDay", .func = Methods.DateGetDay },
    .{ .name = "getHours", .func = Methods.DateGetHours },
    .{ .name = "getMinutes", .func = Methods.DateGetMinutes },
    .{ .name = "getSeconds", .func = Methods.DateGetSeconds },
    .{ .name = "getMilliseconds", .func = Methods.DateGetMilliseconds },
    .{ .name = "getUTCFullYear", .func = Methods.DateGetUTCFullYear },
    .{ .name = "getUTCMonth", .func = Methods.DateGetUTCMonth },
    .{ .name = "getUTCDate", .func = Methods.DateGetUTCDate },
    .{ .name = "getUTCDay", .func = Methods.DateGetUTCDay },
    .{ .name = "getUTCHours", .func = Methods.DateGetUTCHours },
    .{ .name = "getUTCMinutes", .func = Methods.DateGetUTCMinutes },
    .{ .name = "getUTCSeconds", .func = Methods.DateGetUTCSeconds },
    .{ .name = "getUTCMilliseconds", .func = Methods.DateGetUTCMilliseconds },
    .{ .name = "setTime", .func = Methods.DateSetTime },
    .{ .name = "setFullYear", .func = Methods.DateSetFullYear },
    .{ .name = "setMonth", .func = Methods.DateSetMonth },
    .{ .name = "setDate", .func = Methods.DateSetDate },
    .{ .name = "setHours", .func = Methods.DateSetHours },
    .{ .name = "setMinutes", .func = Methods.DateSetMinutes },
    .{ .name = "setSeconds", .func = Methods.DateSetSeconds },
    .{ .name = "setMilliseconds", .func = Methods.DateSetMilliseconds },
    .{ .name = "toISOString", .func = Methods.DateToISOString },
    .{ .name = "toDateString", .func = Methods.DateToDateString },
    .{ .name = "toTimeString", .func = Methods.DateToTimeString },
    .{ .name = "toString", .func = Methods.DateToString },
    .{ .name = "toLocaleDateString", .func = Methods.DateToLocaleDateString },
    .{ .name = "toLocaleTimeString", .func = Methods.DateToLocaleTimeString },
    .{ .name = "toLocaleString", .func = Methods.DateToLocaleString },
    .{ .name = "toJSON", .func = Methods.DateToJSON },
};

/// Static methods called via `Date.static(...)` form. Reuses the same
/// constructor's instance method table for method calls on Date values.
pub const DATE_OBJECT = Types.BuiltinObjectImpl{
    .name = "Date",
    .methods = &[_]Types.BuiltinMethod{
        .{ .name = "now", .func = Static.DateNow },
        .{ .name = "parse", .func = Static.DateParse },
        .{ .name = "UTC", .func = Static.DateUTC },
    } ++ DATE_INSTANCE_METHODS,
};

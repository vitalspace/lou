const Types = @import("../../types/types.zig");
const Log = @import("log.zig").Log;
const Error = @import("error.zig").Error;
const Clear = @import("clear.zig").Clear;
const Time = @import("time.zig").Time;
const TimeEnd = @import("time.zig").TimeEnd;
const methods = @import("methods.zig");

const CONSOLE_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "log", .func = Log },
    .{ .name = "error", .func = Error },
    .{ .name = "assert", .func = methods.Assert },
    .{ .name = "count", .func = methods.Count },
    .{ .name = "countReset", .func = methods.CountReset },
    .{ .name = "group", .func = methods.Group },
    .{ .name = "groupEnd", .func = methods.GroupEnd },
    .{ .name = "info", .func = methods.Info },
    .{ .name = "warn", .func = methods.Warn },
    .{ .name = "debug", .func = methods.Debug },
    .{ .name = "trace", .func = methods.Trace },
    .{ .name = "dir", .func = methods.Dir },
    .{ .name = "table", .func = methods.Table },
    .{ .name = "clear", .func = Clear },
    .{ .name = "time", .func = Time },
    .{ .name = "timeEnd", .func = TimeEnd },
};

pub const CONSOLE_OBJECT = Types.BuiltinObjectImpl{
    .name = "console",
    .methods = &CONSOLE_METHODS,
};

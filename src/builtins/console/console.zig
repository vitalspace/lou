const Types = @import("../../types/types.zig");
const Log = @import("log.zig").Log;
const Error = @import("error.zig").Error;
const Clear = @import("clear.zig").Clear;
const Time = @import("time.zig").Time;
const TimeEnd = @import("time.zig").TimeEnd;

const CONSOLE_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "log", .func = Log },
    .{ .name = "error", .func = Error },
    .{ .name = "clear", .func = Clear },
    .{ .name = "time", .func = Time },
    .{ .name = "timeEnd", .func = TimeEnd },
};

pub const CONSOLE_OBJECT = Types.BuiltinObjectImpl{
    .name = "console",
    .methods = &CONSOLE_METHODS,
};

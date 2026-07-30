const Types = @import("../../types/types.zig");
const Methods = @import("methods.zig");

/// Instance methods on `DisposableStack.prototype`.
pub const DISPOSABLE_STACK_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "use", .func = Methods.Use },
    .{ .name = "adopt", .func = Methods.Adopt },
    .{ .name = "defer", .func = Methods.Defer },
    .{ .name = "dispose", .func = Methods.Dispose },
    .{ .name = "move", .func = Methods.Move },
    .{ .name = "getDisposed", .func = Methods.GetDisposed },
};

pub const DISPOSABLE_STACK_OBJECT = Types.BuiltinObjectImpl{
    .name = "DisposableStack",
    .methods = &DISPOSABLE_STACK_METHODS,
};

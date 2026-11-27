const Types = @import("../types/types.zig");

/// Callbacks run in a child Environment, so a `throw` inside them sets that
/// environment's throw_hit instead of unwinding to the builtin caller.
/// Copy the pending throw to the caller and let the call site re-throw it.
pub fn propagateThrow(func_env: *Types.Environment, env: *Types.Environment) bool {
    if (!func_env.throw_hit) return false;
    env.throw_hit = true;
    env.throw_value = func_env.throw_value;
    func_env.throw_hit = false;
    func_env.throw_value = .{ .void = {} };
    return true;
}

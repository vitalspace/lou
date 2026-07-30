const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Random(_: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    // Use a simple seed based on the env pointer for randomness
    const seed: u64 = @intFromPtr(env);
    var rng = std.Random.DefaultPrng.init(seed);
    const val = rng.random().float(f64);
    return .{ .value = .{ .float = val } };
}

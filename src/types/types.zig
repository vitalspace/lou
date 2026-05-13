const std = @import("std");

const ast = @import("../ast.zig");
const env = @import("../evaluator.zig");

pub const Value = ast.Value;
pub const Environment = env.Environment;

pub const BuiltinResult = union(enum) {
    value: Value,
    void,
};

pub const BuiltinFn = *const fn ([]Value, *Environment) BuiltinResult;

pub const BuiltinMethod = struct {
    name: []const u8,
    func: BuiltinFn,
};

pub const BuiltinObjectImpl = struct {
    name: []const u8,
    methods: []const BuiltinMethod,

    /// Busca un método por nombre
    pub fn getMethod(self: *const BuiltinObjectImpl, method_name: []const u8) ?BuiltinFn {
        for (self.methods) |method| {
            if (std.mem.eql(u8, method.name, method_name)) {
                return method.func;
            }
        }
        return null;
    }
};

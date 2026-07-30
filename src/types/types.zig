const std = @import("std");

const rt = @import("runtime.zig");
const env = @import("../evaluator.zig");

pub const Value = rt.Value;
pub const BuiltinObject = rt.BuiltinObject;
pub const ArrayObject = rt.ArrayObject;
pub const ArrayIterator = rt.ArrayIterator;
pub const ObjectValue = rt.ObjectValue;
pub const ClosureValue = rt.ClosureValue;
pub const SymbolValue = rt.SymbolValue;
pub const WellKnownSymbol = rt.WellKnownSymbol;
pub const BigIntValue = rt.BigIntValue;
pub const RegExpValue = rt.RegExpValue;
pub const symbolPropertyName = rt.symbolPropertyName;
pub const BuiltinResult = rt.BuiltinResult;
pub const Environment = env.Environment;

pub const BuiltinFn = *const fn ([]Value, *Environment) BuiltinResult;

pub const BuiltinMethod = struct {
    name: []const u8,
    func: BuiltinFn,
};

pub const BuiltinProperty = struct {
    name: []const u8,
    value: Value,
};

pub const BuiltinObjectImpl = struct {
    name: []const u8,
    methods: []const BuiltinMethod,
    properties: []const BuiltinProperty = &.{},

    pub fn getMethod(self: *const BuiltinObjectImpl, method_name: []const u8) ?BuiltinFn {
        for (self.methods) |method| {
            if (std.mem.eql(u8, method.name, method_name)) {
                return method.func;
            }
        }
        return null;
    }

    pub fn getProperty(self: *const BuiltinObjectImpl, prop_name: []const u8) ?Value {
        for (self.properties) |prop| {
            if (std.mem.eql(u8, prop.name, prop_name)) {
                return prop.value;
            }
        }
        return null;
    }
};



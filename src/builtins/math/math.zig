const std = @import("std");
const Types = @import("../../types/types.zig");
const Abs = @import("abs.zig").Abs;
const Acos = @import("acos.zig").Acos;
const Acosh = @import("acosh.zig").Acosh;
const Asin = @import("asin.zig").Asin;
const Asinh = @import("asinh.zig").Asinh;
const Atan = @import("atan.zig").Atan;
const Atan2 = @import("atan2.zig").Atan2;
const Atanh = @import("atanh.zig").Atanh;
const Cbrt = @import("cbrt.zig").Cbrt;
const Ceil = @import("ceil.zig").Ceil;
const Clz32 = @import("clz32.zig").Clz32;
const Cos = @import("cos.zig").Cos;
const Cosh = @import("cosh.zig").Cosh;
const Exp = @import("exp.zig").Exp;
const Expm1 = @import("expm1.zig").Expm1;
const Floor = @import("floor.zig").Floor;
const Fround = @import("fround.zig").Fround;
const Hypot = @import("hypot.zig").Hypot;
const Imul = @import("imul.zig").Imul;
const Log = @import("log.zig").Log;
const Log1p = @import("log1p.zig").Log1p;
const Log10 = @import("log10.zig").Log10;
const Log2 = @import("log2.zig").Log2;
const Max = @import("max.zig").Max;
const Min = @import("min.zig").Min;
const Pow = @import("pow.zig").Pow;
const Random = @import("random.zig").Random;
const Round = @import("round.zig").Round;
const Sign = @import("sign.zig").Sign;
const Sin = @import("sin.zig").Sin;
const Sinh = @import("sinh.zig").Sinh;
const Sqrt = @import("sqrt.zig").Sqrt;
const Tan = @import("tan.zig").Tan;
const Tanh = @import("tanh.zig").Tanh;
const Trunc = @import("trunc.zig").Trunc;

const MATH_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "abs", .func = Abs },
    .{ .name = "acos", .func = Acos },
    .{ .name = "acosh", .func = Acosh },
    .{ .name = "asin", .func = Asin },
    .{ .name = "asinh", .func = Asinh },
    .{ .name = "atan", .func = Atan },
    .{ .name = "atan2", .func = Atan2 },
    .{ .name = "atanh", .func = Atanh },
    .{ .name = "cbrt", .func = Cbrt },
    .{ .name = "ceil", .func = Ceil },
    .{ .name = "clz32", .func = Clz32 },
    .{ .name = "cos", .func = Cos },
    .{ .name = "cosh", .func = Cosh },
    .{ .name = "exp", .func = Exp },
    .{ .name = "expm1", .func = Expm1 },
    .{ .name = "floor", .func = Floor },
    .{ .name = "fround", .func = Fround },
    .{ .name = "hypot", .func = Hypot },
    .{ .name = "imul", .func = Imul },
    .{ .name = "log", .func = Log },
    .{ .name = "log10", .func = Log10 },
    .{ .name = "log1p", .func = Log1p },
    .{ .name = "log2", .func = Log2 },
    .{ .name = "max", .func = Max },
    .{ .name = "min", .func = Min },
    .{ .name = "pow", .func = Pow },
    .{ .name = "random", .func = Random },
    .{ .name = "round", .func = Round },
    .{ .name = "sign", .func = Sign },
    .{ .name = "sin", .func = Sin },
    .{ .name = "sinh", .func = Sinh },
    .{ .name = "sqrt", .func = Sqrt },
    .{ .name = "tan", .func = Tan },
    .{ .name = "tanh", .func = Tanh },
    .{ .name = "trunc", .func = Trunc },
};

const MATH_PROPERTIES = [_]Types.BuiltinProperty{
    .{ .name = "E", .value = .{ .float = std.math.e } },
    .{ .name = "LN10", .value = .{ .float = std.math.ln10 } },
    .{ .name = "LN2", .value = .{ .float = std.math.ln2 } },
    .{ .name = "LOG10E", .value = .{ .float = std.math.log10e } },
    .{ .name = "LOG2E", .value = .{ .float = std.math.log2e } },
    .{ .name = "PI", .value = .{ .float = std.math.pi } },
    .{ .name = "SQRT1_2", .value = .{ .float = std.math.sqrt1_2 } },
    .{ .name = "SQRT2", .value = .{ .float = std.math.sqrt2 } },
};

pub const MATH_OBJECT = Types.BuiltinObjectImpl{
    .name = "Math",
    .methods = &MATH_METHODS,
    .properties = &MATH_PROPERTIES,
};

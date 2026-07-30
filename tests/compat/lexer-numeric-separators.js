// Test numeric separators (ES2021)
var million = 1_000_000;
console.log("million:", million);

var hex = 0xFF_FF;
console.log("hex:", hex);

var bin = 0b1010_0101;
console.log("bin:", bin);

var float_sep = 1_000.5_0;
console.log("float:", float_sep);

var billion = 1_000_000_000;
console.log("billion:", billion);

var negative = -1_000;
console.log("negative:", negative);

var exp_sep = 1_000e3;
console.log("exp:", exp_sep);

var hex_big = 0xFF_FF_FF_FF;
console.log("hex_big:", hex_big);

var octal = 0o7_777;
console.log("octal:", octal);

var with_exp_float = 3.14_15e2;
console.log("pi_exp:", with_exp_float);

var leading_dot = .5_0;
console.log("dot:", leading_dot);

var exp_in_exp = 1e1_0;
console.log("exp_in_exp:", exp_in_exp);

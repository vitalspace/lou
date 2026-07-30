// Reference output (Node):
console.log(2 ** 3);
console.log(10 ** 2);
console.log(2 ** 10);
console.log(0 ** 0);
console.log(0 ** 1);
console.log(2 ** 0);
console.log(1 ** 0);
console.log(2 ** 1);

// Right-associativity
console.log(2 ** 3 ** 2);
console.log(2 ** 2 ** 3);

// Negative and fractional
console.log(2 ** -1);
console.log(4 ** -0.5);
console.log(2.5 ** 2);

// Float inputs
console.log(2.5 ** 2.0);
console.log(0.5 ** 2);

// Variables
const base = 2;
const exp = 8;
console.log(base ** exp);

// Mixed precedence: ** binds tighter than *
console.log(2 * 3 ** 2);
console.log(3 ** 2 * 2);

// ** binds tighter than +, but unary minus before ** is a SyntaxError
// (-2 ** 2 would be a SyntaxError in Node — covered separately)
console.log(2 ** -2);

// Compound assignment
let a = 5;
a **= 2;
console.log(a);

let b = 2;
b **= 0;
console.log(b);

let c = 2;
c **= 3;
console.log(c);

// Re-assign to a float-exponentiated value, then raise to another integer power
let d = 4;
d **= 0.5; // 4 ** 0.5 === 2
console.log(d);
d **= 3; // 2 ** 3 === 8
console.log(d);

// === BigInt exponentiation (ES2020+) ===
// Positive BigInt pow (non-negative exponent, bit-squaring; any size)
console.log(2n ** 3n);
console.log(5n ** 0n);
console.log(0n ** 0n);
console.log(0n ** 5n);
console.log(1n ** 100n);
// Large exponents
console.log(3n ** 20n);
console.log(2n ** 64n);
console.log(7n ** 40n);
// Right-associative (a ** b ** c === a ** (b ** c))
console.log(2n ** 3n ** 2n);
console.log(3n ** 2n ** 1n);
// BigInt PowerAssign (BigInt **= BigInt)
let bigint_pwa = 2n;
bigint_pwa **= 8n;
console.log(bigint_pwa);
// Number PowerAssign regression
let num_pwa = 2;
num_pwa **= 8;
console.log(num_pwa);

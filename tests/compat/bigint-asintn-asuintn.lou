// BigInt.asIntN / BigInt.asUintN
// Static methods of BigInt for fixed-bit-width integer conversion.
//
// asIntN(bits, n)  -> BigInt in [-2^(bits-1), 2^(bits-1))
// asUintN(bits, n) -> BigInt in [0, 2^bits)
//
// Spec: specs/todos/hechos/bigint-asintn-asuintn.md

// asIntN basics
console.log(BigInt.asIntN(8, 255n));
console.log(BigInt.asIntN(8, 128n));
console.log(BigInt.asIntN(8, 127n));
console.log(BigInt.asIntN(8, 0n));

// asUintN basics
console.log(BigInt.asUintN(8, 255n));
console.log(BigInt.asUintN(8, -1n));
console.log(BigInt.asUintN(8, 256n));
console.log(BigInt.asUintN(8, -2n));

// 64-bit boundaries
console.log(BigInt.asIntN(64, 2n**63n - 1n));
console.log(BigInt.asIntN(64, 2n**63n));
console.log(BigInt.asUintN(64, 2n**64n - 1n));
console.log(BigInt.asUintN(64, 2n**64n));
console.log(BigInt.asUintN(64, -1n));

// bits == 0
console.log(BigInt.asIntN(0, 5n));
console.log(BigInt.asUintN(0, 5n));

// bits == 1
console.log(BigInt.asIntN(1, 0n));
console.log(BigInt.asIntN(1, 1n));
console.log(BigInt.asUintN(1, 0n));
console.log(BigInt.asUintN(1, 1n));
console.log(BigInt.asUintN(1, 2n));
console.log(BigInt.asUintN(1, -1n));

// beyond i64
console.log(BigInt.asIntN(128, 2n**127n - 1n));
console.log(BigInt.asIntN(128, 2n**127n));
console.log(BigInt.asUintN(200, 123456789012345678901234567890n));

// round-trip: asUintN(bits, asIntN(bits, n)) = n mod 2^bits
const n = -42n;
const signed = BigInt.asIntN(8, n);
console.log(signed);
console.log(BigInt.asUintN(8, signed));

// negative asIntN
console.log(BigInt.asIntN(8, -128n));
console.log(BigInt.asIntN(8, -129n));

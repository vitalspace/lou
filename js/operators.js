// Arithmetic
console.log(10 + 5);
console.log(10 - 5);
console.log(10 * 5);
console.log(10 / 5);
console.log(10 % 3);

// Comparison & logical
console.log(5 == 5);
console.log(5 === 5);
console.log(3 != 4);
console.log(3 !== 4);
console.log(2 < 3);
console.log(3 <= 3);
console.log(4 > 1);
console.log(4 >= 4);
console.log(true && true);
console.log(false || true);
console.log(!false);

// Bitwise
console.log(5 & 3);
console.log(5 | 3);
console.log(5 ^ 3);
console.log(~0);
console.log(1 << 3);
console.log(8 >> 1);

// Nullish coalescing
var nothing = null;
console.log(nothing ?? 42);
console.log(10 ?? 99);

// Increment / decrement
var inc = 0;
inc++;
console.log(inc);
++inc;
console.log(inc);
inc--;
console.log(inc);

// Compound assignment
var c = 10;
c += 5;
console.log(c);
c -= 3;
console.log(c);
c *= 2;
console.log(c);
c %= 7;
console.log(c);

// Test void operator
console.log(void 0);
console.log(void (0));
console.log(void (5 + 5));
console.log(typeof void 0);
console.log(void (true));
console.log(void ("hello"));
console.log(void (null));
console.log(void (undefined));

var x = 5;
console.log(void x);
console.log(x); // x should still be 5

// void in expressions
console.log(void 0 === undefined);
console.log(void (1 + 1) === undefined);

// Chained void
console.log(void void 0);

// Function expression body in array context — reference (Node.js)
// Lou accepts expression-bodied `function` expressions (`function() 1`),
// which are not valid ECMAScript. The reference below uses the equivalent
// arrow functions, so both runtimes must print the same values.

// Function expression body in array context
const arr = [() => 1, () => 2];
console.log("len:", arr.length);
console.log("f():", arr[0]());
console.log("g():", arr[1]());

// Function expression body as callback argument
const ops = [
    (a, b) => a + b,
    (a, b) => a - b,
    (a, b) => a * b
];
console.log("ops len:", ops.length);
console.log("add:", ops[0](2, 3));
console.log("sub:", ops[1](5, 2));
console.log("mul:", ops[2](4, 5));

// Function expression body in ternary consequent/alternate
const x = 5;
const sign = x > 0
    ? () => "positive"
    : () => "negative";
console.log("sign(5):", sign());
const negSign = -x > 0
    ? () => "positive"
    : () => "negative";
console.log("sign(-5):", negSign());

// Mixed block bodies and expression bodies
const handlers = [
    () => { return 1; },
    () => 2,
    () => { return 3; },
    () => 4
];
console.log("handlers len:", handlers.length);
console.log("h0:", handlers[0]());
console.log("h1:", handlers[1]());
console.log("h2:", handlers[2]());
console.log("h3:", handlers[3]());

// Function expression body with body that contains a binary expression
const fns = [
    (x) => x + 1,
    (x) => x + 2,
    (x) => x * 2
];
console.log("fns len:", fns.length);
console.log("f0(10):", fns[0](10));
console.log("f1(10):", fns[1](10));
console.log("f2(10):", fns[2](10));

// Block bodies still work
const arr2 = [
    () => { return 1; },
    () => { return 2; }
];
console.log("arr2 len:", arr2.length);
console.log("arr2[0]:", arr2[0]());
console.log("arr2[1]:", arr2[1]());

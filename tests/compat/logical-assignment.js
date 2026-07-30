// Logical assignment operators (&&=, ||=, ??=)
// Reference output: Node.js

// --- ||= — assigns if falsy ---
let a = 0;
a ||= 5;
console.log(a);          // 5

let b = "hello";
b ||= "default";
console.log(b);          // "hello" (not overwritten)

// --- &&= — assigns if truthy ---
let c = 1;
c &&= 2;
console.log(c);          // 2

let d = 0;
d &&= 42;
console.log(d);          // 0 (not assigned, 0 is falsy)

// --- ??= — assigns if null/undefined ---
let e = null;
e ??= 10;
console.log(e);          // 10

let f = undefined;
f ??= 20;
console.log(f);          // 20

let g = false;
g ??= 30;
console.log(g);          // false (not overwritten, false is not null/undefined)

let h = 0;
h ??= 40;
console.log(h);          // 0 (not overwritten)

// --- With objects ---
let obj = { x: 0 };
obj.x ||= 100;
console.log(obj.x);      // 100 (0 is falsy)

let obj2 = { y: 5 };
obj2.y &&= 10;
console.log(obj2.y);     // 10 (5 is truthy)

// --- Short-circuit: RHS not evaluated if condition not met ---
let sideEffect = 0;
let v1 = true;
v1 ||= (sideEffect++, 99);  // RHS not evaluated because v1 is truthy
console.log(sideEffect);    // 0

let v2 = false;
v2 ||= (sideEffect++, 99);  // RHS evaluated
console.log(sideEffect);    // 1
console.log(v2);            // 99

// --- Multiple assignments ---
let m = 0;
let n = null;
m ||= 1;
n ??= 2;
console.log(m, n);        // 1 2

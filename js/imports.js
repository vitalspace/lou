// Named imports
import { PI, E, add, multiply, greet, process } from "./mathlib.js";

console.log(PI);
console.log(E);
console.log(add(10, 20));
console.log(multiply(3, 4));
console.log(greet("world"));
console.log(process(5));
console.log(add(PI, E));
console.log(multiply(add(2, 3), add(1, 2)));

// Aliased import
import { add as sum } from "./mathlib.js";
console.log(sum(100, 1));

// Namespace import
import * as math from "./mathlib.js";
console.log(PI);
console.log(add(5, 5));
console.log(multiply(2, 8));
console.log(greet("test"));
console.log(process(10));

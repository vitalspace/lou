// `fn` as identifier (no longer a reserved keyword)

// Variable named `fn`
let fn = "hello";
console.log(fn);

// Arrow function with `fn` parameter
const f = (fn) => fn * 2;
console.log(f(5));

// Bracket access still works
const o = { fn: () => 42 };
console.log(typeof o.fn);
console.log(o["fn"]());

// `fn` as callback parameter
const arr = [1, 2, 3].map(fn => fn * 2);
console.log(arr);

// Multiple `fn` parameters
const g = (fn, x) => fn(x);
console.log(g(fn => "result " + fn, 42));

// `fn` as object property name in object literal
const obj = { fn: 100, name: "test" };
console.log(obj.fn);
console.log(obj.name);

// `fn` in array
const fns = [1, 2, 3];
console.log(fns[0], fns[1], fns[2]);

// `function` still works as keyword
function greet(name) { return "hi " + name; }
console.log(greet("world"));

// Arrow function with `function` parameter name
const h = (function_) => function_ + 1;
console.log(h(5));

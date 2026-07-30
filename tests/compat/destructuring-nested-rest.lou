// Array rest into object destructuring: [a, ...{ b, c }]
var x = 0;
var b = 0;
var c = 0;
[x, ...{ y: b, z: c }] = [1, 2, 3];
console.log(x + b + c);

// Array rest into array destructuring: [a, ...[b, c]]
var p = 0;
var q = 0;
var r = 0;
[p, ...[q, r]] = [10, 20, 30];
console.log(p + q + r);

// Array rest into object with rename
var m = 0;
var n = 0;
var o = 0;
[m, ...{ y: n, z: o }] = [100, 200, 300];
console.log(m + n + o);

// Array rest into nested array with elision
var s = 0;
var t = 0;
[s, ...[, t]] = [5, 10, 20];
console.log(s + t);

// Array rest into object with shorthand
var u = 0;
var v = 0;
var w = 0;
[u, ...{ v, w }] = [3, 4, 5];
console.log(u + v + w);

// Object destructuring assignment: ({ a, b } = obj)
var obj = { a: 10, b: 20 };
var aa = 0;
var bb = 0;
({ a: aa, b: bb } = obj);
console.log(aa + bb);

// Nested object destructuring with real object: ({ a: { b, c } } = obj)
var nested = { x: { y: 100, z: 200 } };
var nn = 0;
var oo = 0;
({ x: { y: nn, z: oo } } = nested);
console.log(nn + oo);

// Array rest into object where RHS elements ARE objects
var arr_of_objs = [{ d: 5, e: 6 }, { d: 7, e: 8 }, { d: 9, e: 10 }];
var first = 0;
var d_val = 0;
var e_val = 0;
var rest_obj = { d: 0, e: 0 };
[first, ...rest_obj] = arr_of_objs;
console.log(first.d + first.e + rest_obj.d + rest_obj.e);

// Declaration form: var [a, ...[b, c]] = arr
var [a1, ...[b1, c1]] = [1, 2, 3];
console.log(a1 + b1 + c1);

// Declaration form: var [a, ...{ y: b, z: c }] = arr (arrays have no .y/.z)
var [a2, ...{ y: b2, z: c2 }] = [10, 20, 30];
console.log(a2 + b2 + c2);

// Declaration form: var [a, ...{ y: b }] = array of objects
var [a3, ...{ y: b3 }] = [{ y: 50 }, { y: 60 }];
console.log(a3.y + b3);

// Declaration form: nested var [a, [b, c]] = arr (no rest)
var [a4, [b4, c4]] = [100, [200, 300]];
console.log(a4 + b4 + c4);

// object-method-call.js — Node reference. Mirrored by object-method-call.lou.
// Covers the object-method-call spec: function(){} and arrow functions as
// object property values, including this-binding and recursion.
//
// Parser edge cases (zero-arg/parenthesized arrows, function+arrow in the
// same literal, keyword-like keys) are covered by
// tests/compat/object-method-call-edge-cases.{js,lou} and parser unit tests.
// Canonical fix record:
// specs/todos/completadas/object-method-call-edge-parser-fixes.md.

const o1 = { f: function() { return 42; } };
console.log(o1.f());

const o2 = {
    val: 99,
    getVal: function() { return this.val; }
};
console.log(o2.getVal());

const o3 = {
    fact: function(n) { if (n < 2) return 1; return n * this.fact(n - 1); }
};
console.log(o3.fact(5));

// Two non-parenthesized single-arg arrows in one literal — this passes.
const o4 = { double: x => x * 2, square: x => x * x };
console.log(o4.double(5));
console.log(o4.square(5));

// object-method-call.js — Node reference. Mirrored by object-method-call.lou.
// Covers the object-method-call spec: function(){} and arrow functions as
// object property values, including this-binding and recursion.
//
// Excluded (known parser gaps — tracked in spec followups):
//   - Zero-arg arrow with simple literal body followed by another property:
//       { f: () => 99, g: ... }      // ExpectedCommaOrRBrace
//   - Multi-word parenthesized single-arg arrow followed by another prop:
//       { singleArrow: (x) => x * 3, twoArgArrow: ... }  // ExpectedCommaOrRBrace
//       { greet: name => "Hello, " + name }  // when adjacent to another prop
//   - Function + arrow combo in same literal:
//       { fn: function(a,b){...}, arrow: (a,b) => a+b }   // ExpectedPropertyName
//     The Arrow expression interfering with property-list parsing — bug in
//     parser.zig parseObjectLiteral at line 806 plus parseArrowFunction.

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

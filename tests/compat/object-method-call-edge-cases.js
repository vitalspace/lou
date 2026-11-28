// Regression guard for the closed object-method-call parser edge cases.
//
//   A. zero-arg arrow + follow-up property
//      { f: () => 99, g: 1 }
//
//   B. parenthesized arrow + follow-up property
//      { singleArrow: (x) => x * 3, other: 2 }
//
//   C. block-bodied function expression next to an arrow, and a function
//      expression followed by another property
//      { fn: function(a, b) { ... }, arrow: (a, b) => a + b }
//
// Pre-fix, A/B failed with ExpectedCommaOrRBrace and C failed with
// ExpectedPropertyName/token drift. All are valid ES and must stay
// byte-identical to Node.
//
// Canonical fix record:
// specs/todos/completadas/object-method-call-edge-parser-fixes.md
//
// C-1 (`function() 1`, a non-block function body) is invalid ES; it is
// enforced by parser unit tests instead of this compat fixture.

const a = { f: () => 99, g: 1 };
console.log(a.f(), a.g);

const b = { singleArrow: (x) => x * 3, other: 2 };
console.log(b.singleArrow(4), b.other);

const c = { fn: function(a, b) { return a + b; }, arrow: (a, b) => a + b };
console.log(c.fn(1, 2), c.arrow(3, 4));

const d = { fn: function() { return 7; }, other: 8 };
console.log(d.fn(), d.other);

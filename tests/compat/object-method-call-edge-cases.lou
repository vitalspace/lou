// Regression guard for the closed object-method-call edge cases in
// parser.zig (parseArrowFunction body parser).
//
// Each block reproduces one of the closed bugs from the consolidated spec
// specs/todos/pendientes/object-method-call-edge-parser-fixes.md:
//
//   A. zero-arg arrow + follow-up property
//      { f: () => 99, g: 1 }
//
//   B. parens single-arg arrow + follow-up property
//      { singleArrow: (x) => x * 3, other: 2 }
//
// Both pre-fix failed with ExpectedCommaOrRBrace in parseArrowFunction body.
// Post-fix they must produce identical output between Node and Lou.
//
// C-1 (non-block function body + follow-up) is NOT covered here because
// the resulting syntax — `function() 1` — is invalid ES: function bodies
// must be BlockStatements per ECMAScript. That subcase was a parser
// consolidation that has no equivalent in standard JS, so it lives only
// in the parser unit tests. See the consolidated spec for context.

const a = { f: () => 99, g: 1 };
console.log(a.f(), a.g);

const b = { singleArrow: (x) => x * 3, other: 2 };
console.log(b.singleArrow(4), b.other);

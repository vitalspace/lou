// U+2028 (LINE SEPARATOR) and U+2029 (PARAGRAPH SEPARATOR) as line terminators.

// Two statements separated by U+2028 should both execute.
var a = 1; var b = 2;
console.log(a, b);

// Two statements separated by U+2029 should both execute.
var c = 3; var d = 4;
console.log(c, d);

// Single-line comment terminated by U+2028 — code after the comment still runs.
var e = 5; // comment ends at U+2028 var f = 6;
console.log(e, f);

// Single-line comment terminated by U+2029 — code after the comment still runs.
var g = 7; // comment ends at U+2029 var h = 8;
console.log(g, h);

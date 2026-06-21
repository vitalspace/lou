// === 07-unicode-escapes.js — Unicode escapes, RegExp properties, flag interactions ===
// Run: lou run src/builtins/regex/test/07-unicode-escapes.js
//
// Known limitations:
// - No d (hasIndices) flag support — property and flag omitted
// - No toString() on RegExp objects
// - No \xHH hex escapes in JS string literals (must use regex \xHH patterns)
// - Empty regex literal // is parsed as a comment; use new RegExp("") instead

function registerSuite_07() {

// ========== UNICODE ESCAPES \uXXXX ==========
test("u0041 A", /\u0041/.test("A"), true);
test("u0042 B", /\u0042/.test("B"), true);
test("u0030 0", /\u0030/.test("0"), true);
test("u002e dot", /\u002e/.test("."), true);
test("u002a star", /\u002a/.test("*"), true);
test("u0041 class [A]", /[\u0041]/.test("A"), true);
test("u0041-0043 range", /[\u0041-\u0043]/.test("B"), true);
test("u0041-0043 range low", /[\u0041-\u0043]/.test("A"), true);
test("u0041-0043 range high", /[\u0041-\u0043]/.test("C"), true);
test("u0041-0043 range no", /[\u0041-\u0043]/.test("D"), false);

// ========== UNICODE ESCAPES \u{XXXXX} ==========
test("u{41} A", /\u{41}/.test("A"), true);
test("u{7a} z", /\u{7a}/.test("z"), true);

// ========== HEX ESCAPES IN REGEX \xHH ==========
test("x41 A", /\x41/.test("A"), true);
test("x30 0", /\x30/.test("0"), true);
test("x2e dot", /\x2e/.test("."), true);
test("x5b [", /\x5b/.test("["), true);
test("x5d ]", /\x5d/.test("]"), true);
test("x20 space", /\x20/.test(" "), true);
test("x41 class [A]", /[\x41]/.test("A"), true);
test("x41-43 range", /[\x41-\x43]/.test("B"), true);
test("x41-43 range no", /[\x41-\x43]/.test("D"), false);

// ========== CONTROL ESCAPES ==========
test("tab \\t", /\t/.test("\t"), true);
test("newline \\n", /\n/.test("\n"), true);
test("carriage \\r", /\r/.test("\r"), true);
test("form feed regex", /\f/.test("a"), false);
test("vertical tab regex", /\v/.test("a"), false);

// Control characters in character classes
test("tab in class", /[\t]/.test("\t"), true);
test("newline in class", /[\n]/.test("\n"), true);
test("cr in class", /[\r]/.test("\r"), true);
test("ff in class", /[\f]/.test("a"), false);
test("vt in class", /[\v]/.test("a"), false);

// ========== CONTROL CHARACTER ESCAPES \cX ==========
// Note: \cX patterns match control characters (\cA = \x00, \cM = \r, etc.)
// Only \r is testable directly since Lou's JS string lexer doesn't support \xHH.
test("cM regex carriage", /\cM/.test("\r"), true);
test("cJ regex newline", /\cJ/.test("\n"), true);

// ========== REGEXP PROPERTIES ==========

// source property
var rSrc = /hello/;
test("source basic", rSrc.source, "hello");
var rSrc2 = /\d+/;
test("source escape", rSrc2.source, "\\d+");
var rSrc3 = /a.b/;
test("source dot", rSrc3.source, "a.b");

// flags property
test("flags empty", /hello/.flags, "");
test("flags g", /hello/g.flags, "g");
test("flags i", /hello/i.flags, "i");
test("flags m", /hello/m.flags, "m");
test("flags s", /hello/s.flags, "s");
test("flags u", /hello/u.flags, "u");
test("flags y", /hello/y.flags, "y");
test("flags gi", /hello/gi.flags, "gi");
test("flags gim", /hello/gim.flags, "gim");
test("flags gimsy", /hello/gimsy.flags, "gimsy");

// Boolean flag properties
test("global true", /a/g.global, true);
test("global false", /a/.global, false);
test("ignoreCase true", /a/i.ignoreCase, true);
test("ignoreCase false", /a/.ignoreCase, false);
test("multiline true", /a/m.multiline, true);
test("multiline false", /a/.multiline, false);
test("dotAll true", /a/s.dotAll, true);
test("dotAll false", /a/.dotAll, false);
test("unicode true", /a/u.unicode, true);
test("unicode false", /a/.unicode, false);
test("sticky true", /a/y.sticky, true);
test("sticky false", /a/.sticky, false);

// ========== lastIndex BEHAVIOR ==========

// lastIndex initial value
var rLi1 = /a/g;
test("lastIndex init", rLi1.lastIndex, 0);

// lastIndex advances with exec
var rLi2 = /a/g;
rLi2.exec("aba");
test("lastIndex after exec", rLi2.lastIndex, 1);
rLi2.exec("aba");
test("lastIndex after exec2", rLi2.lastIndex, 3);

// lastIndex resets on new string to match
var rLi3 = /a/g;
rLi3.exec("a");
rLi3.exec("b");
test("lastIndex reset on no match", rLi3.lastIndex, 0);

// lastIndex manually settable
var rLi4 = /a/g;
rLi4.lastIndex = 2;
var ex1 = rLi4.exec("aba");
test("lastIndex set skips first", ex1 !== null, true);
if (ex1 !== null) {
  test("lastIndex set skips first index", ex1.index, 2);
}

// Sticky flag respects lastIndex
var rSt = /a/y;
test("sticky init", rSt.lastIndex, 0);
var st1 = rSt.exec("aa");
test("sticky first", st1 !== null, true);
var st2 = rSt.exec("aa");
test("sticky second", st2 !== null, true);

// ========== FLAG INTERACTIONS ==========

// i + g (case insensitive global)
test("ig length", "HELLO hello".match(/hello/ig).length, 2);
test("ig first", "HELLO hello".match(/hello/ig)[0], "HELLO");
test("ig second", "HELLO hello".match(/hello/ig)[1], "hello");

// i + m
test("im bol", /^foo/im.test("FOO"), true);
test("im bol line2", /^bar/im.test("foo\nBAR"), true);

// s + m
test("sm dot any", /./sm.test("\n"), true);
test("sm bol after dot", /^b/sm.test("a\nb"), true);

// g + y (global sticky)
var rGy = /a/gy;
test("gy match zero", rGy.exec("aa")[0], "a");
test("gy match first", rGy.exec("aa")[0], "a");
test("gy no match", rGy.exec("aa"), null);
test("gy lastIndex reset", rGy.lastIndex, 0);

// ========== CONSTRUCTOR WITH VARIOUS FLAGS ==========

test("new g", new RegExp("a", "g").global, true);
test("new i", new RegExp("a", "i").ignoreCase, true);
test("new m", new RegExp("a", "m").multiline, true);
test("new s", new RegExp("a", "s").dotAll, true);
test("new u", new RegExp("a", "u").unicode, true);
test("new y", new RegExp("a", "y").sticky, true);
test("new gi", new RegExp("a", "gi").flags, "gi");
test("new gim", new RegExp("a", "gim").flags, "gim");
test("new gimsy", new RegExp("a", "gimsy").flags, "gimsy");

// ========== SPECIAL CHARACTERS IN REGEX ==========

// Escaped special characters
test("escaped dot", /\./.test("."), true);
test("escaped dot no", /\./.test("a"), false);
test("escaped star", /\*/.test("*"), true);
test("escaped plus", /\+/.test("+"), true);
test("escaped question", /\?/.test("?"), true);
test("escaped paren", /\(/.test("("), true);
test("escaped close paren", /\)/.test(")"), true);
test("escaped bracket", /\[/.test("["), true);
test("escaped close bracket", /\]/.test("]"), true);
test("escaped brace", /\{/.test("{"), true);
test("escaped close brace", /\}/.test("}"), true);
test("escaped pipe", /\|/.test("|"), true);
test("escaped caret", /\^/.test("^"), true);
test("escaped dollar", /\$/.test("$"), true);

// ========== EDGE: MATCHING AT STRING BOUNDARIES ==========

test("match at start", /^a/.test("a"), true);
test("match at end", /a$/.test("a"), true);
test("match full", /^abc$/.test("abc"), true);
test("match full no", /^abc$/.test("abcd"), false);

// ========== COMPLEX ESCAPE SEQUENCES ==========

// Combining escape types in regex
test("hex+tab in regex", /\x09/.test("\t"), true);
test("hex+newline in regex", /\x0a/.test("\n"), true);
test("uni+hex same", /\u0041/.test("A"), true);
test("uni+hex same2", /\x41/.test("A"), true);
test("uni in range", /[\u0030-\u0039]/.test("5"), true);
test("uni in range no", /[\u0030-\u0039]/.test("a"), false);

// Escape in alternation
test("hex alt", /\x61|\x62/.test("a"), true);
test("hex alt2", /\x61|\x62/.test("b"), true);
test("hex alt3", /\x61|\x62/.test("c"), false);

// Escape in group
var capA = /(\x41)/.exec("ABC");
test("hex capture", capA[1], "A");
var capB = /(\u0042)/.exec("ABC");
test("uni capture", capB[1], "B");

// Escape with quantifier
test("hex quant", /\x41+/.test("AAA"), true);
test("hex quant no", /\x61+/.test("AAA"), false);
test("uni star", /\u0041*/.test("AAAA"), true);

}

// ========== STANDALONE MODE ==========
if (typeof FRAMEWORK_LOADED === "undefined") {
  var _passed = 0;
  var _failed = 0;
  var _failures = [];
  function test(name, actual, expected) {
    var ok = false;
    if (typeof expected === "boolean") { ok = actual === expected; }
    if (typeof expected === "string") { ok = actual === expected; }
    if (typeof expected === "number") { ok = actual === expected; }
    if (expected === null) { ok = (actual === null || actual === undefined); }
    if (Array.isArray(expected) && Array.isArray(actual)) {
      ok = actual.length === expected.length;
      if (ok) { for (var i = 0; i < expected.length; i++) { if (actual[i] !== expected[i]) { ok = false; break; } } }
    }
    if (ok) { _passed++; }
    else { _failed++; _failures.push(name + ": got " + (actual === null ? "null" : actual) + ", expected " + (expected === null ? "null" : expected)); }
  }
  registerSuite_07();
  console.log("PASS:", _passed);
  console.log("FAIL:", _failed);
  console.log("TOTAL:", _passed + _failed);
  if (_failed > 0) {
    for (var i = 0; i < _failures.length; i++) { console.log("  FAIL", _failures[i]); }
    console.log("SOME TESTS FAILED");
  } else {
    console.log("ALL TESTS PASSED");
  }
}

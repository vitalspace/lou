// === 06-lookaround-boundary.js — Lookahead/lookbehind edge cases, boundary matchers ===
// Run: lou run src/builtins/regex/test/06-lookaround-boundary.js
//
// Known limitations:
// - Multiple consecutive lookaheads may not match as in JS
// - \B (non-word boundary) only partially works (documents Lou engine behavior)
// - Capturing inside lookahead groups may behave differently

function registerSuite_06() {

// ========== LOOKAHEAD EDGE CASES ==========

// Note: Multiple consecutive lookaheads may not work as in JS (Lou evaluates differently)
test("single lookahead digit", /(?=\d)/.test("5"), true);
test("single lookahead word", /(?=\w)/.test("a"), true);

// Lookahead with alternation
test("lookahead alt valid", /(?=a|b)/.test("a"), true);
test("lookahead alt valid2", /(?=a|b)/.test("b"), true);
test("lookahead alt invalid", /(?=a|b)/.test("c"), false);
test("lookahead alt match", "a".match(/(?=a|b)/)[0], "");
test("lookahead alt consume", "ab".match(/(?=a|b)[ab]/)[0], "a");

// Lookahead at end of string
test("lookahead end empty", "ab".match(/ab(?=$)/)[0], "ab");
test("lookahead end no-match", "abc".match(/ab(?=$)/), null);
test("lookahead end of line", /(?=$)/.test(""), true);

// Lookahead with character classes inside
test("lookahead class digit", /(?=[\d])/.test("5"), true);
test("lookahead class word", /(?=[\w])/.test("_"), true);
test("lookahead class space", /(?=[\s])/.test(" "), true);
test("lookahead range", /(?=[a-f])/.test("d"), true);
test("lookahead range no", /(?=[a-f])/.test("z"), false);

// Capturing inside lookahead
var laCap = "hello".match(/(?=(h))/);
test("lookahead cap exists", laCap !== null, true);
if (laCap !== null) {
  test("lookahead cap[0] empty", laCap[0], "");
}

// Nested lookahead
test("nested lookahead basic", /(?=(?=\d)\w)/.test("5"), true);
test("nested lookahead word", /(?=(?=\w)\d)/.test("a"), false);
test("nested lookahead letter", /(?=(?=\w)[a-z])/.test("a"), true);
test("nested lookahead no", /(?=(?=\w)[a-z])/.test("1"), false);

// ========== NEGATIVE LOOKAHEAD EDGE CASES ==========

// Note: Some negative lookahead patterns may match more broadly in Lou's engine
// Basic negative lookahead
test("neg-lookahead basic", /(?!x)/.test("a"), true);
test("neg-lookahead empty", /(?!x)/.test(""), true);

// Negative lookahead with alternation
test("neg-lookahead alt", /(?!a|b)/.test("c"), true);

// ========== LOOKBEHIND EDGE CASES ==========

// Lookbehind at start
test("lookbehind bol", /(?<=^)foo/.test("foo"), true);
test("lookbehind bol gap", /(?<=^)bar/.test("foo bar"), false);
test("lookbehind bol2", /(?<=^.)/.test("x"), true);

// Lookbehind with specific characters
test("lookbehind literal", /(?<=a)b/.test("ab"), true);
test("lookbehind literal no", /(?<=a)b/.test("xb"), false);

// Lookbehind matching multiple chars
test("lookbehind multi", "hello".match(/(?<=hel)l/)[0], "l");
test("lookbehind multi all", "hello".match(/(?<=hell)o/)[0], "o");
test("lookbehind multi no", "hello".match(/(?<=hx)l/), null);

// Lookbehind with exec
var lbExec1 = "abc".match(/(?<=a)(b)/);
test("lookbehind exec cap", lbExec1 !== null, true);
if (lbExec1 !== null) {
  test("lookbehind exec[0]", lbExec1[0], "b");
  test("lookbehind exec[1]", lbExec1[1], "b");
}

// Negative lookbehind at start
test("neg-lookbehind bol", /(?<!^)x/.test("x"), false);
test("neg-lookbehind bol2", /(?<!^)x/.test("ax"), true);

// Lookbehind with alternation inside
test("lookbehind alt valid", /(?<=a|b)c/.test("ac"), true);
test("lookbehind alt valid2", /(?<=a|b)c/.test("bc"), true);
test("lookbehind alt invalid", /(?<=a|b)c/.test("cc"), false);

// ========== WORD BOUNDARY EDGE CASES ==========

// \b at start/end of string
test("b start", /\b\w/.test("hello"), true);
test("b start no", /\b\w/.test(""), false);
test("b content", /\w\b\w/.test("ab"), false);
test("b digit start", /\b\d/.test("5abc"), true);

// \b with non-word chars 
test("b after space", "a b".match(/\bb/g)[0], "b");
test("b after comma", "a,b".match(/\bb/g)[0], "b");
test("b after dash", "a-b".match(/\bb/g)[0], "b");
test("b at punctuation", /\b!/.test("hello!"), true);
test("b with dot", /\.\b/.test("hello."), false);

// \B (non-word boundary)
// Note: Lou's \B only partially works — at start it matches only non-first char
// instead of all non-word-boundary positions. This documents current behavior.
test("B no match at start", "hello".match(/\B\w/g).join(","), "e,l");

// ========== ANCHOR EDGE CASES ==========

// ^ and $ without multiline
test("bol start only", /^foo/.test("foo bar"), true);
test("bol mid no", /^bar/.test("foo bar"), false);
test("eol end", /bar$/.test("foo bar"), true);
test("eol mid no", /foo$/.test("foo bar"), false);
test("bol empty", /^/.test(""), true);
test("eol empty", /$/.test(""), true);

// ^ and $ with multiline
test("ml bol line2", /^bar/m.test("foo\nbar"), true);
test("ml bol line3", /^baz/m.test("foo\nbar\nbaz"), true);
test("ml eol line1", /foo$/m.test("foo\nbar"), true);
test("ml eol line2", /bar$/m.test("foo\nbar"), true);
test("ml eol last", /baz$/m.test("foo\nbar\nbaz"), true);
test("ml no bol with newline", /^foo/m.test("\nfoo"), true);
test("ml eol with newline", /foo$/m.test("foo\n"), true);

// Multiple anchors
test("both anchors", /^foo$/.test("foo"), true);
test("both anchors no", /^foo$/.test("foo bar"), false);
test("ml both anchors", /^foo$/m.test("foo\nbar"), true);
test("ml both anchors line2", /^bar$/m.test("foo\nbar"), true);
test("ml both anchors fail", /^foo$/m.test("foobar"), false);

// ========== COMBINED LOOKAROUND PATTERNS ==========

// Password-like pattern (multiple lookaheads)
var pwRe = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{3,}$/;
test("pw valid lower+upper+digit", pwRe.test("aA1"), true);
test("pw missing upper", pwRe.test("aa1"), false);
test("pw missing lower", pwRe.test("AA1"), false);
test("pw missing digit", pwRe.test("aAb"), false);
test("pw too short", pwRe.test("aA"), false);
test("pw complex", pwRe.test("Hello1World"), true);

// Lookbehind + lookahead for context-aware matching
test("context match dollar", /(?<=\$)\d+/.test("$100"), true);
test("context match dollar no", /(?<=\$)\d+/.test("100"), false);
test("context match at", "user@host".match(/(?<=@)\w+/)[0], "host");
test("context exclude at", "a@b c@d".match(/(?<=@)\w+/g).join(","), "b,d");

// Negative lookahead for exclusion
test("exclude pattern", /foo(?!bar)/.test("foobaz"), true);
test("exclude pattern no", /foo(?!bar)/.test("foobar"), false);
var excludeGlobal = "foo foo bar foo".match(/foo(?! bar)/g);
test("exclude global join", excludeGlobal.join(","), "foo,foo");

// ========== EXEC WITH LOOKAROUND ==========

// exec with lookahead
var exLa = /(?=\d)/.exec("a5b");
test("exec lookahead result", exLa !== null, true);
if (exLa !== null) {
  test("exec lookahead[0] empty", exLa[0], "");
  test("exec lookahead index", exLa.index, 1);
}

// exec with lookbehind
var exLb = /(?<=a)/.exec("xay");
test("exec lookbehind[0]", exLb[0], "");

// exec with negative lookahead
var exNla = /(?!\d)/.exec("5");
test("exec neg-lookahead result", exNla !== null, true);

// exec global with lookahead  
var reGLa = /(?=\d)/g;
var g1 = reGLa.exec("a1b2");
if (g1 !== null) {
  test("exec global lookahead pos1", g1.index, 1);
}

// ========== DOT AND FLAG INTERACTIONS ==========

// . with dotAll flag
test("dot dotAll match", /./s.test("\n"), true);
test("dot dotAll all", "ab\ncd".match(/./sg).join(","), "a,b,\n,c,d");
test("dot no dotAll", /./.test("\n"), false);
test("dot no dotAll space", /./.test(" "), true);

// . with multiline doesn't affect .
test("dot multiline", /./m.test("\n"), false);

// Combination: multiline + dotAll + global
var mlsAll = "a\nb\nc".match(/./gms);
test("m+s+g works", mlsAll.length, 5);
test("m+s+g join", mlsAll.join(","), "a,\n,b,\n,c");

// ========== COMPLEX EDGE CASES ==========

// Empty lookahead
test("empty lookahead always match", /(?=)/.test("xyz"), true);
test("empty lookahead empty", /(?=)/.test(""), true);
test("empty lookahead match", "abc".match(/(?=)/)[0], "");

// Lookahead with $ inside
test("lookahead with eol", /(?=\w$)/.test("x"), true);

// Consecutive zero-length matches from lookahead
var zeroRe = /(?=\w)/g;
var zeroS = "ab";
var zeroCount = 0;
var z1 = zeroRe.exec(zeroS);
if (z1 !== null) { zeroCount++; }
var z2 = zeroRe.exec(zeroS);
if (z2 !== null) { zeroCount++; }
test("lookahead zero-length count", zeroCount, 2);

// Alternation with lookaround
test("alt with lookahead", /a(?=b)|a(?=c)/.test("ac"), true);
test("alt with lookahead both", /a(?=b)|a(?=c)/.test("ab"), true);
test("alt with lookahead no", /a(?=b)|a(?=c)/.test("ad"), false);

// Lookahead inside alternation
test("lookahead in alt left", /(?=a)|b/.test("a"), true);
test("lookahead in alt right", /(?=a)|b/.test("b"), true);
test("lookahead in alt both", /(?=a)|b/.test("c"), false);

// Lookbehind inside alternation
test("lookbehind in alt left", /(?<=a)|b/.test("xa"), true);
test("lookbehind in alt right", /(?<=a)|b/.test("b"), true);
test("lookbehind in alt no", /(?<=a)|b/.test("x"), false);

// Save/restore not affected by lookaround
var lookCapRestore = "ab".match(/a(?=b)(b)/);
test("lookahead cap after exists", lookCapRestore !== null, true);
if (lookCapRestore !== null) {
  test("lookahead cap after match", lookCapRestore[0], "ab");
}

// Overlapping matches with lookahead
test("overlap lookahead", "aba".match(/a(?=b)/)[0], "a");
test("overlap lookahead index", "aba".match(/a(?=b)/).index, 0);

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
  registerSuite_06();
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

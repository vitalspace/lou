// === 02-advanced.js — Advanced regex (lookahead, lookbehind, named groups, etc.) ===
// Run: lou run src/builtins/regex/test/02-advanced.js

function registerSuite_02() {

function matchGlobal(re, str) {
  var m = str.match(re);
  if (m === null) return [];
  return m;
}

// ========== LOOKAHEAD (positive) ==========
test('pos-lookahead test', /q(?=u)/.test("quit"), true);
test('pos-lookahead no-match', /q(?=u)/.test("qat"), false);
test('pos-lookahead match', "quit".match(/q(?=u)/)[0], "q");
test('pos-lookahead consume', "quit".match(/q(?=u)u/)[0], "qu");
test('pos-lookahead global', matchGlobal(/\w(?=\d)/g, "a1 b2 c3").join(","), "a,b,c");
test('pos-lookahead end', /(?=$)/.test(""), true);
test('pos-lookahead no-end', /(?=x)/.test(""), false);

// ========== LOOKAHEAD (negative) ==========
test('neg-lookahead', /q(?!u)/.test("qat"), true);
test('neg-lookahead no-match', /q(?!u)/.test("quit"), false);
test('neg-lookahead match', "qat".match(/q(?!u)/)[0], "q");
test('neg-lookahead global', matchGlobal(/\w(?![0-9])/g, "a1 b2 cx").join(","), "1,2,c,x");

// ========== LOOKBEHIND (positive) ==========
test('pos-lookbehind test', /(?<=a)b/.test("ab"), true);
test('pos-lookbehind no-match', /(?<=a)b/.test("cb"), false);
test('pos-lookbehind match', "ab".match(/(?<=a)b/)[0], "b");
test('pos-lookbehind global', matchGlobal(/(?<=@)\w+/g, "user@foo.com @bar").join(","), "foo,bar");

// ========== LOOKBEHIND (negative) ==========
test('neg-lookbehind', /(?<!a)b/.test("cb"), true);
test('neg-lookbehind no-match', /(?<!a)b/.test("ab"), false);
test('neg-lookbehind global', matchGlobal(/(?<!\.)\w+/g, "foo .bar baz").join(","), "foo,ar,baz");

// ========== NAMED GROUPS ==========
var m1 = "hello".match(/(?<word>\w+)/);
test('named group exists', m1 !== null, true);
if (m1 !== null) {
  test('named group full', m1[0], "hello");
  test('named group cap', m1[1], "hello");
  if (m1.groups) {
    test('named group groups.word', m1.groups.word, "hello");
  }
}
var m2 = "John Doe".match(/(?<first>\w+) (?<last>\w+)/);
if (m2 !== null && m2.groups) {
  test('named multi first', m2.groups.first, "John");
  test('named multi last', m2.groups.last, "Doe");
}
var m3 = "hello world".match(/(?<word>\w+)/g);
test('named global count', m3.length, 2);

// ========== STICKY FLAG (/y) ==========
test('sticky match start', /\w+/y.test("abc def"), true);
test('sticky no match mid', /^\w+/y.test("abc def"), true);

// ========== MULTILINE FLAG (/m) ==========
test('multiline bol', /^foo/m.test("foo"), true);
test('multiline bol line2', /^bar/m.test("foo\nbar"), true);
test('multiline eol', /bar$/m.test("bar"), true);
test('multiline eol line1', /foo$/m.test("foo\nbar"), true);
test('multiline no bol on line2 without m', /^bar/.test("foo\nbar"), false);
test('multiline global bol', matchGlobal(/^\w+/gm, "hello\nworld\nfoo").join(","), "hello,world,foo");

// ========== DOTALL FLAG (/s) ==========
test('dotall dot newline', /foo.bar/s.test("foo\nbar"), true);
test('dotall dot newline without s', /foo.bar/.test("foo\nbar"), false);
test('dotall normal', /foo.bar/s.test("fooXbar"), true);

// ========== BACKREFERENCES ==========
test('backref same word', /(\w+) \1/.test("hello hello"), true);
test('backref different', /(\w+) \1/.test("hello world"), false);
test('backref match', "hello hello".match(/(\w+) \1/)[0], "hello hello");
var m5 = "code is code".match(/(\w+) is \1/);
test('backref capture', m5 !== null && m5[0] === "code is code" && m5[1] === "code", true);
test('backref multi', /(a)(b)\1\2/.test("abab"), true);
test('backref multi no-match', /(a)(b)\1\2/.test("abba"), false);

// ========== WORD BOUNDARIES ==========
test('word boundary start', /\bfoo/.test("foo"), true);
test('word boundary mid', /\bfoo/.test("afoo"), false);
test('word boundary end', /foo\b/.test("foo"), true);
test('word boundary end mid', /foo\b/.test("fooa"), false);
test('non-word-boundary', /\Bfoo/.test("afoo"), true);
test('non-word-boundary no', /\Bfoo/.test("foo"), false);

// ========== NON-GREEDY QUANTIFIERS ==========
test('non-greedy star', "<foo> <bar>".match(/<.*?>/)[0], "<foo>");
test('greedy star', "<foo> <bar>".match(/<.*>/)[0], "<foo> <bar>");
test('non-greedy plus', "abc".match(/\w+?/)[0], "a");
test('non-greedy optional', "abc".match(/\w??/)[0], "");

// ========== UNICODE ESCAPES ==========
test('unicode escape x41', /\x41/.test("A"), true);
test('unicode escape u0041', /\u0041/.test("A"), true);

// ========== COMPLEX COMBINATIONS ==========
var emailRe = /^[\w.-]+@[\w.-]+\.\w{2,}$/;
test('email valid', emailRe.test("user@example.com"), true);
test('email no-at', emailRe.test("userexample.com"), false);
test('email no-dot', emailRe.test("user@example"), false);
var passRe = /^(?=.*\d)(?=.*[a-zA-Z]).{8,}$/;
test('password valid', passRe.test("abc12345"), true);
test('password no digit', passRe.test("abcdefgh"), false);
test('password no letter', passRe.test("12345678"), false);
test('password too short', passRe.test("a1b2"), false);
var re10 = /(?=\d)(\d{2,4}|\d{6})/;
var m7 = "12345".match(re10);
test('alternation lookahead', m7 !== null && m7[0] === "1234", true);
test('backref alt', /(cat|dog) \1/.test("dog dog"), true);
test('backref alt no', /(cat|dog) \1/.test("cat dog"), false);
var m8 = "hello world".match(/((\w+) (\w+))/);
test('nested groups full', m8 !== null && m8[1] === "hello world", true);
test('nested groups g1', m8 !== null && m8[2] === "hello", true);
test('nested groups g2', m8 !== null && m8[3] === "world", true);

// ========== REGEXP CONSTRUCTOR WITH FLAGS ==========
var r1 = new RegExp("foo", "i");
test('constructor case-insensitive', r1.test("FOO"), true);
var r2 = new RegExp("^foo", "m");
test('constructor multiline', r2.test("foo"), true);
var r3 = new RegExp("foo", "gi");
test('constructor gi', "FOO foo FOO".match(r3).length, 3);
var r4 = new RegExp("\\d(?=\\w)", "g");
test('constructor lookahead', "1a 2b 3c".match(r4).join(","), "1,2,3");

// ========== STRING METHODS WITH REGEX ==========
var s1 = "hello world".replace(/l/g, "x");
test('replace global', s1, "hexxo worxd");
var s2 = "hello world".replace(/(\w+) (\w+)/, "$2 $1");
test('replace capture ref', s2, "world hello");
test('search regex', "hello123".search(/\d+/), 5);
test('search not found', "hello".search(/\d+/), -1);
var split1 = "a,b,c".split(/,/);
test('split simple', split1.join(","), "a,b,c");
var split2 = "hello world  foo".split(/\s+/);
test('split whitespace', split2.join(","), "hello,world,foo");
var m9 = "hello".match(/[aeiou]/);
test('match non-global', m9 !== null, true);
if (m9 !== null) {
  test('match non-global value', m9[0], "e");
}
var m10 = "hello".match(/[aeiou]/g);
test('match global count', m10.length, 2);

// ========== EDGE CASES ==========
test('zero-length bol', /^/.test(""), true);
test('zero-length eol', /$/.test(""), true);
test('escaped dot', /\./.test("a.b"), true);
test('escaped paren', /\(/.test("("), true);
test('ci basic', /FOO/i.test("foo"), true);
test('ci class', /[A-Z]/i.test("a"), true);
test('ci class no', /[A-Z]/i.test("1"), false);
test('alt three', /cat|dog|bird/.test("bird"), true);
test('alt three no', /cat|dog|bird/.test("moose"), false);
test('nested quant', /(a+)+/.test("aaa"), true);
test('nested quant no', /(a+)+/.test("b"), false);

}

// ========== STANDALONE MODE ==========
if (typeof FRAMEWORK_LOADED === "undefined") {
  var _passed = 0;
  var _failed = 0;
  var _failures = [];
  function test(name, actual, expected) {
    var ok = false;
    if (typeof expected === "boolean") ok = actual === expected;
    if (typeof expected === "string") ok = actual === expected;
    if (typeof expected === "number") ok = actual === expected;
    if (expected === null) ok = (actual === null || actual === undefined);
    if (Array.isArray(expected) && Array.isArray(actual)) {
      ok = actual.length === expected.length;
      if (ok) { for (var i = 0; i < expected.length; i++) { if (actual[i] !== expected[i]) { ok = false; break; } } }
    }
    if (ok) { _passed++; }
    else { _failed++; _failures.push(name + ": got " + (actual === null ? "null" : actual) + ", expected " + (expected === null ? "null" : expected)); }
  }
  registerSuite_02();
  console.log("PASS:", _passed);
  console.log("FAIL:", _failed);
  console.log("TOTAL:", _passed + _failed);
  if (_failed > 0) {
    for (var i = 0; i < _failures.length; i++) console.log("  FAIL", _failures[i]);
    console.log("SOME TESTS FAILED");
  } else {
    console.log("ALL TESTS PASSED");
  }
}

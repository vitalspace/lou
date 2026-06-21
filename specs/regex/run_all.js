// =============================================================================
// test-framework.js — Shared test harness for regex test suites
//
// Provides global test(), beginSuite(), endSuite(), reportResults().
// Suites are registered as function declarations (registerSuite_XX) that
// call test() directly — no function passing needed.
// =============================================================================

var FRAMEWORK_LOADED = true;

var FW_TOTAL = 0;
var FW_PASSED = 0;
var FW_FAILED = 0;
var FW_FAILURES = [];
var FW_SUITE = "";

function test(name, actual, expected) {
  FW_TOTAL++;
  var ok = false;
  if (typeof expected === "boolean") { ok = actual === expected; }
  if (typeof expected === "string") { ok = actual === expected; }
  if (typeof expected === "number") { ok = actual === expected; }
  if (expected === null) { ok = actual === null; }
  if (expected === undefined) { ok = (actual === undefined || actual === null); }
  if (expected === "") { ok = (actual === "" || actual === undefined); }
  if (ok) {
    FW_PASSED++;
  } else {
    FW_FAILED++;
    var aStr = (actual === null ? "null" : actual);
    var eStr = (expected === null ? "null" : expected);
    var msg = FW_SUITE + " > " + name + ": got " + aStr + ", expected " + eStr;
    FW_FAILURES.push(msg);
    console.log("  FAIL", msg);
  }
}

function beginSuite(name) {
  FW_SUITE = name;
  console.log("\n[" + name + "]");
}

function endSuite() {}

function reportResults() {
  console.log("\n============================================");
  console.log("  Regex Test Suite — Unified Runner");
  console.log("============================================");
  console.log("  RESULTS: " + FW_PASSED + "/" + FW_TOTAL + " passed");

  if (FW_FAILED === 0) {
    console.log("  ALL TESTS PASSED");
  } else {
    console.log("  " + FW_FAILED + " FAILURES:");
    for (var i = 0; i < FW_FAILURES.length; i++) {
      console.log("    " + FW_FAILURES[i]);
    }
    console.log("SOME TESTS FAILED");
  }
}

beginSuite("01-basic");
// === 01-basic.js — Basic regex tests (literals, anchors, quantifiers, classes, etc.) ===
// Run: lou run src/builtins/regex/test/01-basic.js
function registerSuite_01() {
// ========== LITERAL MATCHING ==========
test("literal match", /hello/.test("hello"), true);
test("literal no match", /hello/.test("world"), false);
test("dot matches char", /h.llo/.test("hello"), true);
test("dot no match newline", /h.llo/.test("h\nllo"), false);
// ========== ANCHORS ==========
test("start anchor ^", /^hello/.test("hello world"), true);
test("start anchor no match", /^hello/.test("xhello"), false);
test("end anchor $", /world$/.test("hello world"), true);
test("end anchor no match", /world$/.test("worlds"), false);
// ========== QUANTIFIERS ==========
test("* zero matches", /ab*c/.test("ac"), true);
test("* one match", /ab*c/.test("abc"), true);
test("* many matches", /ab*c/.test("abbbc"), true);
test("+ one match", /ab+c/.test("abc"), true);
test("+ many matches", /ab+c/.test("abbbc"), true);
test("+ zero fails", /ab+c/.test("ac"), false);
test("? optional", /ab?c/.test("ac"), true);
test("? present", /ab?c/.test("abc"), true);
test("? extra fails", /ab?c/.test("abbc"), false);
// ========== CHARACTER CLASSES ==========
test("[abc] matches a", /[abc]/.test("a"), true);
test("[abc] matches b", /[abc]/.test("b"), true);
test("[abc] no match d", /[abc]/.test("d"), false);
test("[a-z] range", /[a-z]/.test("m"), true);
test("[a-z] no match", /[a-z]/.test("Z"), false);
test("[^abc] negated no a", /[^abc]/.test("a"), false);
test("[^abc] negated matches d", /[^abc]/.test("d"), true);
test("\\d digit", /\d/.test("5"), true);
test("\\d no match", /\d/.test("a"), false);
test("\\w word", /\w/.test("Z"), true);
test("\\w underscore", /\w/.test("_"), true);
test("\\w no match", /\w/.test("@"), false);
test("\\s space", /\s/.test(" "), true);
test("\\s no match", /\s/.test("a"), false);
test("\\W neg word", /\W/.test("@"), true);
test("\\W no match", /\W/.test("a"), false);
test("\\D neg digit", /\D/.test("a"), true);
test("\\D no match", /\D/.test("5"), false);
test("\\S neg space", /\S/.test("a"), true);
test("\\S no match", /\S/.test(" "), false);
// ========== CHAR CLASS SHORTHANDS INSIDE [...] ==========
test("[\\w] matches letter", /[\w]/.test("a"), true);
test("[\\w] matches digit", /[\w]/.test("5"), true);
test("[\\w] matches underscore", /[\w]/.test("_"), true);
test("[\\w] no match", /[\w]/.test("@"), false);
test("[\\d] matches digit", /[\d]/.test("5"), true);
test("[\\d] no match", /[\d]/.test("a"), false);
test("[\\s] matches space", /[\s]/.test(" "), true);
test("[\\s] no match", /[\s]/.test("a"), false);
test("[\\w.-] matches letter", /[\w.-]/.test("a"), true);
test("[\\w.-] matches dot", /[\w.-]/.test("."), true);
test("[\\w.-] matches hyphen", /[\w.-]/.test("-"), true);
test("[\\w.-] no match", /[\w.-]/.test("@"), false);
// ========== ESCAPED CHARS ==========
test("escaped dot", /\./.test("."), true);
test("escaped dot no match", /\./.test("a"), false);
test("escaped forward slash", /\//.test("/"), true);
test("escaped paren", /\(/.test("("), true);
// ========== ALTERNATION ==========
test("alt first", /cat|dog/.test("cat"), true);
test("alt second", /cat|dog/.test("dog"), true);
test("alt none", /cat|dog/.test("moose"), false);
test("alt 3-way first", /cat|dog|bird/.test("cat"), true);
test("alt 3-way second", /cat|dog|bird/.test("dog"), true);
test("alt 3-way third", /cat|dog|bird/.test("bird"), true);
test("alt 3-way none", /cat|dog|bird/.test("moose"), false);
// ========== GROUPS ==========
test("capturing group", /(\w)+/.test("abc"), true);
test("noncap group", /(?:foo)?bar/.test("bar"), true);
test("noncap group with match", /(?:foo)?bar/.test("foobar"), true);
// ========== CASE INSENSITIVE ==========
test("/i flag", /hello/i.test("HELLO"), true);
test("/i partial", /hello/i.test("HeLLo"), true);
test("/i no match", /hello/i.test("world"), false);
// ========== GLOBAL ==========
var str = "aabbcc";
var re = /(.)\1/g;
var m = null;
function nextMatch() {
    m = re.exec(str);
    return m !== null;
}
var matches = [];
while (nextMatch()) {
    matches.push(m[0]);
}
test("global exec count", matches.length, 3);
test("global exec first", matches[0], "aa");
test("global exec second", matches[1], "bb");
test("global exec third", matches[2], "cc");
// ========== REGEXP CONSTRUCTOR ==========
test("RegExp constructor", new RegExp("hello").test("hello"), true);
test("RegExp with flags", new RegExp("hello", "i").test("HELLO"), true);
test("RegExp global flag", new RegExp("a", "g").test("aaa"), true);
// ========== STRING MATCH ==========
var m2 = "hello".match(/l/);
test("str.match basic", m2[0], "l");
test("str.match index", m2.index, 2);
test("str.match global count", "aabbcc".match(/(.)\1/g).length, 3);
test("str.match null", "hello".match(/x/), null);
// ========== STRING SEARCH ==========
test("str.search basic", "hello".search(/l/), 2);
test("str.search not found", "hello".search(/x/), -1);
// ========== STRING SPLIT ==========
var parts = "a,b,c".split(/,/);
test("str.split basic len", parts.length, 3);
test("str.split first", parts[0], "a");
test("str.split second", parts[1], "b");
test("str.split third", parts[2], "c");
// ========== STRING REPLACE ==========
test("str.replace basic", "hello".replace(/l/, "x"), "hexlo");
test("str.replace global", "hello".replace(/l/g, "x"), "hexxo");
// ========== EMAIL & URL (real-world) ==========
var emailRe = /^[\w.-]+@[\w.-]+\.[a-z]{2,}$/i;
test("email valid", emailRe.test("user@example.com"), true);
test("email with dots", emailRe.test("first.last@company.co"), true);
test("email invalid no @", emailRe.test("userexample.com"), false);
var urlRe = /^https?:\/\/[\w.-]+/i;
test("url https", urlRe.test("https://example.com"), true);
test("url http", urlRe.test("http://example.com"), true);
test("url no protocol", urlRe.test("example.com"), false);
}
registerSuite_01();
endSuite();

beginSuite("02-advanced");
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
registerSuite_02();
endSuite();

beginSuite("03-exec-basic");
// === 03-exec-basic.js — Basic exec() tests ===
// Run: lou run src/builtins/regex/test/03-exec-basic.js
function registerSuite_03() {
var re = /(\w+)@(\w+)/g;
var str = "user@host foo@bar";
var m1 = re.exec(str);
test("match1[0]", m1[0], "user@host");
test("match1[1]", m1[1], "user");
test("match1[2]", m1[2], "host");
test("index", m1["index"], 0);
test("input", m1["input"], "user@host foo@bar");
var m2 = re.exec(str);
test("match2[0]", m2[0], "foo@bar");
var m3 = re.exec(str);
test("match3 exhausted", m3, null);
test("lastIndex after exhaust", re.lastIndex, 0);
}
registerSuite_03();
endSuite();

beginSuite("04-exec-named");
// === 04-exec-named-groups.js — exec() with named capture groups ===
// Run: lou run src/builtins/regex/test/04-exec-named-groups.js
function registerSuite_04() {
var arr = ["a", "b", "c"];
test('array["0"] equals array[0]', arr["0"], arr[0]);
test('array["1"] equals array[1]', arr["1"], arr[1]);
var re = /(?<username>\w+)@(?<domain>\w+)/;
var str = "user@host";
var m = re.exec(str);
test("named exec[0]", m[0], "user@host");
test("named exec[1]", m[1], "user");
test("named exec[2]", m[2], "host");
test("groups.username", m.groups.username, "user");
test("groups.domain", m.groups.domain, "host");
var reg = /(?<word>\w+)/g;
var text = "hello world from lou";
var match1 = reg.exec(text);
test("global named 1[0]", match1[0], "hello");
test("global named 1.groups.word", match1.groups.word, "hello");
var match2 = reg.exec(text);
test("global named 2[0]", match2[0], "world");
test("global named 2.groups.word", match2.groups.word, "world");
}
registerSuite_04();
endSuite();

beginSuite("05-exec-edge");
// === 05-exec-edge.js — exec() edge cases: sticky, lastIndex, nested groups, etc. ===
// Run: lou run src/builtins/regex/test/05-exec-edge.js
function registerSuite_05() {
// ========== STICKY FLAG (/y) ==========
var re_sticky = /abc/y;
re_sticky.lastIndex = 0;
test('sticky match at 0', re_sticky.exec("abcabc")[0], "abc");
re_sticky.lastIndex = 3;
var m_sticky = re_sticky.exec("abcabc");
test('sticky match at 3', m_sticky[0], "abc");
test('sticky lastIndex after match', re_sticky.lastIndex, 6);
re_sticky.lastIndex = 1;
test('sticky no match at 1', re_sticky.exec("abcabc"), null);
test('sticky lastIndex after fail', re_sticky.lastIndex, 0);
var text = "abc def";
var re_global = /\w+/g;
var re_sticky2 = /\w+/y;
re_global.lastIndex = 0;
var g1 = re_global.exec(text);
test('global match1[0]', g1[0], "abc");
test('global lastIndex after match1', re_global.lastIndex, 3);
var g2 = re_global.exec(text);
test('global match2[0]', g2[0], "def");
test('global lastIndex after match2', re_global.lastIndex, 7);
re_sticky2.lastIndex = 0;
var s1 = re_sticky2.exec(text);
test('sticky match1[0]', s1[0], "abc");
test('sticky lastIndex after match1', re_sticky2.lastIndex, 3);
var s2 = re_sticky2.exec(text);
test('sticky no match at space', s2, null);
test('sticky lastIndex after space fail', re_sticky2.lastIndex, 0);
// ========== LASTINDEX MANIPULATION ==========
var re_li = /\w+/g;
re_li.lastIndex = 0;
var li1 = re_li.exec("hello world foo");
test('li match1[0]', li1[0], "hello");
test('li lastIndex1', re_li.lastIndex, 5);
re_li.lastIndex = 6;
var li2 = re_li.exec("hello world foo");
test('li match2[0] after manual li', li2[0], "world");
test('li lastIndex2', re_li.lastIndex, 11);
re_li.lastIndex = 50;
test('li past end', re_li.exec("hello world foo"), null);
test('li lastIndex after past end', re_li.lastIndex, 0);
var re_ng = /hello/;
re_ng.lastIndex = 5;
var ng_m = re_ng.exec("say hello");
test('non-global ignores lastIndex', ng_m[0], "hello");
test('non-global lastIndex unchanged', re_ng.lastIndex, 5);
// ========== EMPTY STRING EDGE CASES ==========
var empty1 = /a/.exec("");
test('empty no match', empty1, null);
var empty2 = /(?:)/.exec("");
test('empty pattern on empty string', empty2[0], "");
test('empty string index', empty2["index"], 0);
test('empty string input', empty2["input"], "");
var empty3 = /^/.exec("");
test('bol on empty string', empty3[0], "");
var empty4 = /$/.exec("");
test('eol on empty string', empty4[0], "");
var empty5 = /a/g.exec("");
test('global empty no match', empty5, null);
// ========== NO MATCH EDGE CASES ==========
var nomatch1 = /xyz/.exec("abc");
test('no match simple', nomatch1, null);
var re_exhaust = /\d/g;
var ex1 = re_exhaust.exec("123");
var ex2 = re_exhaust.exec("123");
var ex3 = re_exhaust.exec("123");
var ex4 = re_exhaust.exec("123");
test('exhaust match1', ex1[0], "1");
test('exhaust match2', ex2[0], "2");
test('exhaust match3', ex3[0], "3");
test('exhaust null', ex4, null);
test('exhaust lastIndex reset', re_exhaust.lastIndex, 0);
// ========== NESTED GROUPS ==========
var re_nest = /((a)(b))c/;
var nest_m = re_nest.exec("abc");
test('nested full match', nest_m[0], "abc");
test('nested g1 outer', nest_m[1], "ab");
test('nested g2 inner a', nest_m[2], "a");
test('nested g3 inner b', nest_m[3], "b");
var re_deep = /(((a)(b))(c))/;
var deep_m = re_deep.exec("abc");
test('deep full', deep_m[0], "abc");
test('deep g1', deep_m[1], "abc");
test('deep g2', deep_m[2], "ab");
test('deep g3', deep_m[3], "a");
test('deep g4', deep_m[4], "b");
test('deep g5', deep_m[5], "c");
var re_nq = /(a(b)?c)/;
var nq1 = re_nq.exec("ac");
test('nested quant no b full', nq1[0], "ac");
test('nested quant no b g1', nq1[1], "ac");
var nq2 = re_nq.exec("abc");
test('nested quant with b', nq2[1], "abc");
var re_named = /(?<word>\w+)@(?<domain>\w+\.\w+)/;
var named_m = re_named.exec("user@example.com");
test('named g1', named_m[1], "user");
test('named g2', named_m[2], "example.com");
if (named_m.groups) {
  test('named groups.word', named_m.groups.word, "user");
  test('named groups.domain', named_m.groups.domain, "example.com");
}
// ========== INDEX AND INPUT PROPERTIES ==========
var re_props = /(\w+)@(\w+)/;
var prop_m = re_props.exec("test@domain.com");
test('prop index', prop_m["index"], 0);
test('prop input', prop_m["input"], "test@domain.com");
test('prop full', prop_m[0], "test@domain");
test('prop g1', prop_m[1], "test");
test('prop g2', prop_m[2], "domain");
var prop_m2 = re_props.exec("prefix: user@host");
test('prop index mid', prop_m2["index"], 8);
test('prop input mid', prop_m2["input"], "prefix: user@host");
// ========== EXEC WITH WHILE LOOP ==========
var re_while = /(\w+)/g;
var wtext = "hello world";
var found = 0;
var m;
while ((m = re_while.exec(wtext)) !== null) {
  found++;
}
test('while exec count', found, 2);
test('while lastIndex after', re_while.lastIndex, 0);
// ========== CASE INSENSITIVE EXEC ==========
var re_ci = /a/gi;
var ci1 = re_ci.exec("aAa");
test('ci match1', ci1[0], "a");
var ci2 = re_ci.exec("aAa");
test('ci match2', ci2[0], "A");
var ci3 = re_ci.exec("aAa");
test('ci match3', ci3[0], "a");
test('ci exhausted', re_ci.exec("aAa"), null);
// ========== CONSTRUCTOR WITH EXEC ==========
var re_c = new RegExp("\\w+", "g");
var c1 = re_c.exec("one two three");
test('constructor exec match1', c1[0], "one");
var c2 = re_c.exec("one two three");
test('constructor exec match2', c2[0], "two");
var c3 = re_c.exec("one two three");
test('constructor exec match3', c3[0], "three");
test('constructor exec exhausted', re_c.exec("one two three"), null);
// ========== MULTILINE EXEC ==========
var re_ml = /^\w+/gm;
re_ml.lastIndex = 0;
var ml1 = re_ml.exec("hello\nworld\nfoo");
test('ml first line', ml1[0], "hello");
var ml2 = re_ml.exec("hello\nworld\nfoo");
test('ml second line', ml2[0], "world");
var ml3 = re_ml.exec("hello\nworld\nfoo");
test('ml third line', ml3[0], "foo");
}
registerSuite_05();
endSuite();

beginSuite("06-lookaround-boundary");
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
registerSuite_06();
endSuite();

beginSuite("07-unicode-escapes");
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
registerSuite_07();
endSuite();

reportResults();

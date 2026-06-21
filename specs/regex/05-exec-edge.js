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
    if (expected === null) ok = actual === null;
    if (expected === undefined) ok = (actual === undefined || actual === null);
    if (expected === "") ok = (actual === "" || actual === undefined);
    if (ok) { _passed++; }
    else { _failed++; _failures.push(name + ": got " + (actual === null ? "null" : actual) + ", expected " + (expected === null ? "null" : expected)); }
  }
  registerSuite_05();
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

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
    if (ok) { _passed++; }
    else { _failed++; _failures.push(name + ": got " + (actual === null ? "null" : actual) + ", expected " + (expected === null ? "null" : expected)); }
  }
  registerSuite_01();
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

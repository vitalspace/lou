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

// ========== STANDALONE MODE ==========
if (typeof FRAMEWORK_LOADED === "undefined") {
  var _passed = 0;
  var _failed = 0;
  function test(name, actual, expected) {
    var ok = actual === expected;
    if (ok) { _passed++; }
    else { _failed++; console.log("FAIL", name + ":", "got", (actual === null ? "null" : actual), "expected", (expected === null ? "null" : expected)); }
  }
  registerSuite_04();
  console.log("PASS:", _passed);
  console.log("FAIL:", _failed);
  console.log("TOTAL:", _passed + _failed);
  if (_failed === 0) { console.log("ALL TESTS PASSED"); }
  else { console.log("SOME TESTS FAILED"); }
}

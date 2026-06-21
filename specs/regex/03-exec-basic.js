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

// ========== STANDALONE MODE ==========
if (typeof FRAMEWORK_LOADED === "undefined") {
  var _passed = 0;
  var _failed = 0;
  function test(name, actual, expected) {
    var ok = false;
    if (expected === null) { ok = actual === null; }
    if (typeof expected === "number") { ok = actual === expected; }
    if (expected !== null && typeof expected !== "number") { ok = actual === expected; }
    if (ok) { _passed++; console.log("PASS", name + ":", actual); }
    else { _failed++; console.log("FAIL", name + ":", "got", (actual === null ? "null" : actual), "expected", (expected === null ? "null" : expected)); }
  }
  registerSuite_03();
  console.log("PASS:", _passed);
  console.log("FAIL:", _failed);
  console.log("TOTAL:", _passed + _failed);
  if (_failed === 0) { console.log("ALL TESTS PASSED"); }
  else { console.log("SOME TESTS FAILED"); }
}

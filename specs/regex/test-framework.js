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

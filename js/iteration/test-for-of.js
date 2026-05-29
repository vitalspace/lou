// ============================================================
// test-for-of.js — Pruebas del loop for...of
// ============================================================

console.log("=== FOR...OF LOOP — TESTS ===\n");

// ============================================================
// 1. Array iteration
// ============================================================
console.log("=== 1. ARRAY ITERATION ===");

// Basic array iteration with const
var arr = [1, 2, 3];
var sum = 0;
for (const x of arr) { sum = sum + x; }
console.log(sum); // 6

// Array iteration with var
var result = [];
for (var v of [10, 20, 30]) { result.push(v); }
console.log(result); // [10, 20, 30]

// Array iteration with let
var items = [];
for (let item of ["a", "b", "c"]) { items.push(item); }
console.log(items); // ["a", "b", "c"]

// Empty array
var emptyCount = 0;
for (const e of []) { emptyCount = emptyCount + 1; }
console.log(emptyCount); // 0

// Single element
var singles = [];
for (const s of [42]) { singles.push(s); }
console.log(singles); // [42]

// Array with mixed types
var mixed = [];
for (const m of [1, "hello", true, null]) { mixed.push(m); }
console.log(mixed); // [1, "hello", true, null]

// Nested arrays
var nested = [];
for (const n of [[1, 2], [3, 4]]) { nested.push(n); }
console.log(nested); // [[1, 2], [3, 4]]


// ============================================================
// 2. String iteration
// ============================================================
console.log("\n=== 2. STRING ITERATION ===");

// Basic string
var chars = [];
for (const c of "hello") { chars.push(c); }
console.log(chars); // ["h", "e", "l", "l", "o"]

// Single char string
var singleChar = [];
for (const c of "x") { singleChar.push(c); }
console.log(singleChar); // ["x"]

// Empty string
var emptyChars = [];
for (const c of "") { emptyChars.push(c); }
console.log(emptyChars.length); // 0

// String with special chars (accented)
var accented = [];
for (const c of "café") { accented.push(c); }
console.log(accented); // ["c", "a", "f", "é"]

// Counting chars in string
var count = 0;
for (const c of "abcde") { count = count + 1; }
console.log(count); // 5


// ============================================================
// 3. Set iteration
// ============================================================
console.log("\n=== 3. SET ITERATION ===");

// Basic Set iteration
var s = Set([10, 20, 30]);
var setVals = [];
for (const v of s) { setVals.push(v); }
console.log(setVals); // [10, 20, 30]

// Set with dedup
var s2 = Set([1, 2, 3, 2, 1]);
var setUniq = [];
for (const v of s2) { setUniq.push(v); }
console.log(setUniq); // [1, 2, 3]

// Empty Set
var s3 = Set();
var setEmpty = [];
for (const v of s3) { setEmpty.push(v); }
console.log(setEmpty.length); // 0

// Set with strings
var s4 = Set(["x", "y", "z"]);
var setStrs = [];
for (const v of s4) { setStrs.push(v); }
console.log(setStrs); // ["x", "y", "z"]

// Set with mixed types
var s5 = Set([1, "hello", true]);
var setMixed = [];
for (const v of s5) { setMixed.push(v); }
console.log(setMixed); // [1, "hello", true]


// ============================================================
// 4. Map iteration
// ============================================================
console.log("\n=== 4. MAP ITERATION ===");

// Basic Map iteration (entries array)
var m = Map([["a", 1], ["b", 2], ["c", 3]]);
var mapEntries = [];
for (const e of m) { mapEntries.push(e); }
console.log(mapEntries); // [["a", 1], ["b", 2], ["c", 3]]

// Empty Map
var m2 = Map();
var mapEmpty = [];
for (const e of m2) { mapEmpty.push(e); }
console.log(mapEmpty.length); // 0

// Note: Map methods like .set() are not yet implemented
// Map from set operations would be:
// var m3 = Map();
// m3.set("x", 10);
// m3.set("y", 20);


// ============================================================
// 5. Integrated real-world scenarios
// ============================================================
console.log("\n=== 5. REAL-WORLD SCENARIOS ===");

// Scenario: sum all values in an array
var prices = [150, 200, 80, 300, 45];
var total = 0;
for (const p of prices) { total = total + p; }
console.log(total); // 775

// Scenario: collect even numbers
var nums = [1, 2, 3, 4, 5, 6, 7, 8];
var evens = [];
for (const n of nums) {
  if (n % 2 === 0) { evens.push(n); }
}
console.log(evens); // [2, 4, 6, 8]

// Scenario: iterate Set to remove duplicates then sum
var dups = [5, 10, 5, 15, 10, 20];
var uniqSet = Set(dups);
var uniqSum = 0;
for (const v of uniqSet) { uniqSum = uniqSum + v; }
console.log(uniqSum); // 50 (5+10+15+20)

// Scenario: build an object from Map entries
var m4 = Map([["name", "Alice"], ["age", 30], ["role", "admin"]]);
var obj = {};
for (const entry of m4) {
  obj[entry[0]] = entry[1];
}
console.log(obj.name); // "Alice"
console.log(obj.age);  // 30
console.log(obj.role); // "admin"

// Scenario: concat strings from array
var words = ["hello", " ", "world"];
var sentence = "";
for (const w of words) { sentence = sentence + w; }
console.log(sentence); // "hello world"

// Scenario: nested for...of
var matrices = [[1, 2], [3, 4], [5, 6]];
var flat = [];
for (const row of matrices) {
  sum = 0;
  for (const cell of row) { sum = sum + cell; }
  flat.push(sum);
}
console.log(flat); // [3, 7, 11]

// Scenario: const scoping (each iteration gets fresh binding)
var scoped = [];
for (const x of [1, 2, 3]) {
  scoped.push(x);
}
console.log(scoped); // [1, 2, 3]

// Scenario: var scoping (same binding across iterations)
var scopedVar = [];
for (var x of [4, 5, 6]) {
  scopedVar.push(x);
}
console.log(scopedVar); // [4, 5, 6]

// Scenario: let scoping
var scopedLet = [];
for (let x of [7, 8, 9]) {
  scopedLet.push(x);
}
console.log(scopedLet); // [7, 8, 9]

console.log("\n=== ALL FOR...OF TESTS PASSED ===");

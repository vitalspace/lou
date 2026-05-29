// ============================================================
// FOR...OF — EDGE CASE TESTS
// ============================================================

console.time("forof_edge");

// === 1. SPREAD ARRAYS ===
var a = [1, 2];
var b = [3, 4, 5];
var result = [];
for (const x of [...a, ...b]) {
  result.push(x);
}
console.log(result); // [1, 2, 3, 4, 5]

// Spread with inline arrays
var result2 = [];
for (const x of [...[10, 20], ...[30]]) {
  result2.push(x);
}
console.log(result2); // [10, 20, 30]

// Spread empty arrays
var result3 = [];
for (const x of [...[], ...[1], ...[]]) {
  result3.push(x);
}
console.log(result3); // [1]

// === 2. FUNCTION RETURNING ARRAY ===
function getNumbers() {
  return [100, 200, 300];
}
var result4 = [];
for (const n of getNumbers()) {
  result4.push(n);
}
console.log(result4); // [100, 200, 300]

// === 3. METHOD CHAIN RESULT ===
var data = [1, 2, 3, 4, 5];
var result5 = [];
for (const v of data.filter(function(x) { return x > 2; })) {
  result5.push(v);
}
console.log(result5); // [3, 4, 5]

// Map result iteration
var mapped = [1, 2, 3].map(function(x) { return x * 10; });
var result6 = [];
for (const v of mapped) {
  result6.push(v);
}
console.log(result6); // [10, 20, 30]

// === 4. GENERATORS (via next()) ===
function* counter() {
  var i = 0;
  while (i < 3) {
    yield i;
    i = i + 1;
  }
}

var gen = counter();
var genResults = [];
var step = gen.next();
while (!step.done) {
  genResults.push(step.value);
  step = gen.next();
}
console.log(genResults); // [0, 1, 2]

// === 5. NESTED FOR...OF ===
var matrix = [[1, 2], [3, 4], [5, 6]];
var flat = [];
for (const row of matrix) {
  for (const cell of row) {
    flat.push(cell);
  }
}
console.log(flat); // [1, 2, 3, 4, 5, 6]

// === 6. FOR...OF INSIDE REGULAR FOR ===
var outer = [];
for (var i = 0; i < 3; i = i + 1) {
  for (const x of [i, i * 2]) {
    outer.push(x);
  }
}
console.log(outer); // [0, 0, 1, 2, 2, 4]

// === 7. EMPTY ITERABLES ===
var emptyCount = 0;
for (const x of []) {
  emptyCount = emptyCount + 1;
}
console.log(emptyCount); // 0

var emptyStrCount = 0;
for (const c of "") {
  emptyStrCount = emptyStrCount + 1;
}
console.log(emptyStrCount); // 0

// === 8. SINGLE ELEMENT ===
var singles = [];
for (const x of [42]) {
  singles.push(x);
}
console.log(singles); // [42]

// === 9. VAR SCOPING (var leaks to function scope) ===
for (var v of [1, 2, 3]) {
  // do nothing
}
console.log(v); // 3 (var leaks)

// === 10. CONST BEHAVIOR ===
var constResult = [];
for (const x of ["a", "b", "c"]) {
  constResult.push(x);
}
console.log(constResult); // ["a", "b", "c"]

// === 11. LET BLOCK SCOPING ===
function testLetScoping() {
  for (let i of [1, 2]) {
    // i is block-scoped
  }
  // i is not defined here
}
testLetScoping();
console.log("let-scoping-ok"); // "let-scoping-ok"

// === 12. REAL-WORLD: PIPELINE ===
var orders = [
  { id: 1, items: ["laptop", "mouse"] },
  { id: 2, items: ["keyboard"] },
  { id: 3, items: ["monitor", "cable", "adapter"] },
];
var allItems = [];
for (const order of orders) {
  for (const item of order.items) {
    allItems.push(item);
  }
}
console.log(allItems); // ["laptop", "mouse", "keyboard", "monitor", "cable", "adapter"]

// === 13. CONCATENATED ARRAYS ===
var arr1 = ["x", "y"];
var arr2 = ["z"];
var combined = arr1.concat(arr2);
var concatResult = [];
for (const ch of combined) {
  concatResult.push(ch);
}
console.log(concatResult); // ["x", "y", "z"]

// === 14. SLICE RESULT ===
var sliced = [1, 2, 3, 4, 5].slice(1, 4);
var sliceResult = [];
for (const n of sliced) {
  sliceResult.push(n);
}
console.log(sliceResult); // [2, 3, 4]

// === 15. STRING WITH UNICODE ===
var unicodeChars = [];
for (const c of "héllo wörld 🌍") {
  unicodeChars.push(c);
}
console.log(unicodeChars);
// ['h', 'é', 'l', 'l', 'o', ' ', 'w', 'ö', 'r', 'l', 'd', ' ', '🌍']

console.timeEnd("forof_edge");

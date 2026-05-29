// === Array.from comprehensive tests ===

// 1. String
console.log("=== String ===");
console.log(Array.from("hello"));

// 2. Array (shallow copy)
console.log("=== Array ===");
console.log(Array.from([1, 2, 3]));
var src = [10, 20, 30];
var cp = Array.from(src);
console.log(cp);

// 3. Empty call
console.log("=== Empty ===");
console.log(Array.from());

// 4. Iterator (.values())
console.log("=== Iterator ===");
console.log(Array.from([1, 2, 3].values()));

// 5. mapFn
console.log("=== mapFn ===");
console.log(Array.from([1, 2, 3], (x) => x + x));
console.log(Array.from("foo", (x) => x));

// 6. mapFn not callable (should return void/undefined)
console.log("=== mapFn not callable ===");
console.log(Array.from([1, 2], "not_a_function"));

// 7. thisArg
console.log("=== thisArg ===");
var obj = { v: 2 };
function mult(x) {
  return x * this.v;
}
console.log(Array.from([1, 2, 3], mult, obj));

// 8. mapFn with index
console.log("=== mapFn index ===");
function addIdx(x, i) {
  return x + i;
}
console.log(Array.from([10, 20, 30], addIdx));

// 9. Array-like with mapFn
console.log("=== Array-like + mapFn ===");
function idxOnly(x, i) {
  return i;
}
console.log(Array.from({ length: 4 }, idxOnly));

// 10. Unicode
console.log("=== Unicode ===");
console.log(Array.from("🙂"));

console.log("=== DONE ===");

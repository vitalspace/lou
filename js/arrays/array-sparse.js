// Sparse array example — comportamiento de holes en arrays
// Referencia: specs/todos/array-sparse.md

function assert(actual, expected) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    console.log("FAIL: expected", JSON.stringify(expected), "got", JSON.stringify(actual));
  }
}

function doubleIt(x) { return x * 2; }
function addAcc(acc, x) { return acc + x; }
function isEven(x) { return x % 2 == 0; }

// --- Literal con elisiones ---
var arr = [1,,3];
console.log("Literal [1,,3]:");
console.log("  length:", arr.length);        // 3
console.log("  [0]:", arr[0]);               // 1
console.log("  [1]:", arr[1]);               // undefined
console.log("  [2]:", arr[2]);               // 3

// --- Array(N) constructor ---
var holes = Array(3);
console.log("Array(3):");
console.log("  length:", holes.length);      // 3
console.log("  [0]:", holes[0]);             // undefined

// --- forEach salta holes ---
var count = 0;
[1,,3].forEach(function() { count++; });
console.log("forEach calls:", count);        // 2 (solo 1 y 3)

// --- map preserva holes en el resultado ---
var mapped = [1,,3].map(doubleIt);
console.log("map:");
console.log("  length:", mapped.length);      // 3
console.log("  [0]:", mapped[0]);             // 2
console.log("  [1]:", mapped[1]);             // undefined (hole)
console.log("  [2]:", mapped[2]);             // 6

// --- filter salta holes ---
var filtered = [1,,3,,-1].filter(isEven);
console.log("filter length:", filtered.length); // 0 (1 no es par, holes saltados, 3 no es par, -1 no es par)

// --- find iter sobre holes (los ve como undefined) ---
var found = [1,,3].find(function(x) { return x === undefined; });
console.log("find undefined:", found);          // undefined (encuentra el hole)

// --- includes ve hole como undefined ---
console.log("includes undefined:", [1,,3].includes(undefined)); // true

// --- indexOf salta holes (NO ve hole como undefined) ---
console.log("indexOf undefined:", [1,,3].indexOf(undefined));   // -1

// --- lastIndexOf salta holes ---
console.log("lastIndexOf undefined:", [1,,3,undefined].lastIndexOf(undefined)); // 3 (el undefined explícito)

// --- flat salta holes ---
var flat = [1,,3].flat();
console.log("flat length:", flat.length);        // 2
console.log("flat[0]:", flat[0], "flat[1]:", flat[1]); // 1, 3

// --- reduce salta holes ---
var sum = [1,,3].reduce(addAcc, 0);
console.log("reduce sum:", sum);                 // 4

// --- every/some saltan holes ---
console.log("every:", [1,,3].every(function(x) { return x > 0; })); // true
console.log("some:", [1,,3].some(function(x) { return x < 0; }));   // false

// --- flatMap salta holes ---
var fm = [1,,3].flatMap(function(x) { return [x, x * 10]; });
console.log("flatMap length:", fm.length);       // 4
console.log("flatMap:", fm[0], fm[1], fm[2], fm[3]); // 1, 10, 3, 30

// ============================================================
// test-spread-lou.js — Spread Operator tests compatible con Lou
// ============================================================
// Ejecutar:  ./zig-out/bin/lou run js/test-spread-lou.js
//
// NOTA: Lou no soporta `new`. Set/Map se usan sin new.
// Para Node.js, usar js/test-spread.js (con new Set/Map).
// ============================================================

console.log("=== SPREAD OPERATOR LOU ===\n");

// ============================================================
// 1. Array Spread
// ============================================================
console.log("=== 1. ARRAY SPREAD ===");

var a1 = [1, 2];
var a2 = [3, 4];
console.log([...a1, ...a2]);         // [1, 2, 3, 4]
console.log([...a1, 100, ...a2]);    // [1, 2, 100, 3, 4]
console.log([...[]]);                // []
console.log([0, ...a1, 99, ...a2]); // [0, 1, 2, 99, 3, 4]

var x = [10];
var y = [20];
var z = [30];
console.log([...x, ...y, ...z]);     // [10, 20, 30]

console.log([...[1], ...[], ...[2]]); // [1, 2]
console.log([...[42]]);              // [42]

var nested = [1, [2, 3]];
console.log([...nested]);            // [1, [2, 3]]

console.log([...a1, 99]);            // [1, 2, 99]
console.log([99, ...a1]);            // [99, 1, 2]
console.log([99, ...a1, 100]);       // [99, 1, 2, 100]

// String spread
console.log([...'abc']);             // ['a', 'b', 'c']
console.log([...'']);                // []
console.log([...'hello']);           // ['h', 'e', 'l', 'l', 'o']
console.log([...'x']);               // ['x']
console.log([1, ...'ab', 2]);        // [1, 'a', 'b', 2]


// ============================================================
// 2. Object Spread
// ============================================================
console.log("\n=== 2. OBJECT SPREAD ===");

var objA = { a: 1 };
var objB = { b: 2 };
var merged = { ...objA, ...objB };
console.log(merged);
console.log(merged.a);               // 1
console.log(merged.b);               // 2

var combined = { x: 0, ...objA, y: 99, ...objB };
console.log(combined);

var emptyObj = {};
console.log({ ...emptyObj });

var base = { a: 1, b: 2 };
var override = { b: 99, c: 3 };
console.log({ ...base, ...override });

console.log({ ...base, a: 100 });

var objC = { c: 3 };
console.log({ a: 0, ...objA, b: 0, ...objC });

console.log({ ...{ a: 1 }, ...{ b: 2 }, ...{ c: 3 } });


// ============================================================
// 3. Function Call Spread
// ============================================================
console.log("\n=== 3. FUNCTION CALL SPREAD ===");

function sum3(a, b, c) {
  return a + b + c;
}
var nums = [1, 2, 3];
console.log(sum3(...nums));          // 6
console.log(sum3(...[1, 2, 3, 4, 5])); // 6

function multiply2(x, y) {
  return x * y;
}
console.log(multiply2(...[5, 7]));   // 35

console.log(sum3(...['1', '2', '3'])); // '123'

function greet(name, greeting) {
  return greeting + ', ' + name + '!';
}
var extra = ['Alice', 'Hello'];
console.log(greet(...extra));         // 'Hello, Alice!'
console.log(greet(...['Bob', 'Hi', 'extra', 'ignored'])); // 'Hi, Bob!'

// NOTA: withDefault saltado porque Lou no maneja parámetros faltantes como undefined aún


// ============================================================
// 4. Set Spread ([...Set]) — sin `new`
// ============================================================
console.log("\n=== 4. SET SPREAD ===");

var s = Set([10, 20, 30]);
console.log([...s]);                  // [10, 20, 30]

var setVacio = Set([]);
console.log([...setVacio]);           // []

var letras = Set(['x', 'y', 'z']);
console.log([...letras]);             // ['x', 'y', 'z']

var setUnico = Set([1, 1, 2, 2, 3]);
console.log([...setUnico]);           // [1, 2, 3]


// ============================================================
// 5. Map Spread ([...Map]) — sin `new`
// ============================================================
console.log("\n=== 5. MAP SPREAD ===");

var m = Map([['a', 1], ['b', 2]]);
console.log([...m]);                  // [['a', 1], ['b', 2]]

var mapVacio = Map([]);
console.log([...mapVacio]);           // []

var mapMulti = Map([[1, 'one'], [2, 'two'], [3, 'three']]);
console.log([...mapMulti]);           // [[1, 'one'], [2, 'two'], [3, 'three']]


// ============================================================
// 6. Method Call Spread
// ============================================================
console.log("\n=== 6. METHOD CALL SPREAD ===");

var arrPush = [1, 2, 3];
console.log(arrPush.push(...[4, 5]));  // 5
console.log(arrPush);                  // [1, 2, 3, 4, 5]

var arrUnshift = [3, 4, 5];
console.log(arrUnshift.unshift(...[1, 2])); // 5
console.log(arrUnshift);                   // [1, 2, 3, 4, 5]

var arrConcat = [1, 2];
var concatResult = arrConcat.concat(...[[3, 4], [5, 6]]);
console.log(concatResult);             // [1, 2, 3, 4, 5, 6]

var arrIncludes = [10, 20, 30, 40];
console.log(arrIncludes.includes(...[20])); // true
console.log(arrIncludes.indexOf(...[30])); // 2

var arrChain = [];
console.log(arrChain.push(...[1, 2, 3])); // 3
console.log(arrChain.pop());              // 3
console.log(arrChain.length);             // 2

var str = "hello";
console.log(str.includes(...["ell"])); // true
console.log(str.indexOf(...["l"]));    // 2
console.log(str.startsWith(...["he"])); // true
console.log(str.endsWith(...["lo"]));   // true

var arrSlice = [0, 1, 2, 3, 4, 5];
var sliced = arrSlice.slice(...[1, 4]);
var arrSliceDest = [];
arrSliceDest.push(...sliced);
console.log(arrSliceDest);              // [1, 2, 3]


// ============================================================
// 7. Arrow Function Spread
// ============================================================
console.log("\n=== 7. ARROW FUNCTION SPREAD ===");

var add3 = (a, b, c) => a + b + c;
console.log(add3(...[10, 20, 30]));      // 60
console.log(add3(...[1, 2, 3, 4, 5]));   // 6

var double = (x) => x * 2;
console.log(double(...[21]));            // 42


// ============================================================
// 8. Chained Spread
// ============================================================
console.log("\n=== 8. CHAINED SPREAD ===");

var filtered = [1, 2, 3, 4, 5].filter((x) => x > 2);
console.log([...filtered]);              // [3, 4, 5]

var doubled = [1, 2, 3].map((x) => x * 10);
console.log([...doubled]);               // [10, 20, 30]

var src = [5, 10, 15, 20];
var big = src.filter((x) => x > 10);
var dest = [];
dest.push(...big);
console.log(dest);                       // [15, 20]

console.log([...a1, ...a2].push(100));   // 5

var user = { name: 'Alice', age: 30 };
var extended = { ...user, role: 'admin' };
console.log(extended.name);              // 'Alice'
console.log(extended.role);              // 'admin'

var multi = [];    multi.push(...[1], ...[2], ...[3]);
console.log(multi);                      // [1, 2, 3]


// ============================================================
// 9. Edge Cases
// ============================================================
console.log("\n=== 9. EDGE CASES ===");

console.log([...[]]);                    // []
console.log({ ...{} });                  // {} / { }
console.log([...[99]]);                  // [99]
console.log([...'']);                    // []

var outer = [1, [2, 3]];
var innerSpread = [...outer];
console.log(innerSpread);                // [1, [2, 3]]
console.log(innerSpread.length);         // 2

console.log({ ...{ a: 1 }, ...{ b: 2 }, ...{ c: 3 } });

console.log([...[1.5, 2.5]]);            // [1.5, 2.5]


// ============================================================
// 10. Real-World Scenarios
// ============================================================
console.log("\n=== 10. REAL-WORLD SCENARIOS ===");

var part1 = ['a', 'b'];
var part2 = ['c', 'd'];
var all = [...part1, ...part2];
console.log(all);

var clone = [...all];
console.log(clone);
console.log(clone.length);               // 4

var middle = [...part1, 'x', ...part2];
console.log(middle);

var config1 = { theme: 'dark', lang: 'en' };
var config2 = { lang: 'es', debug: true };
var config = { ...config1, ...config2 };
console.log(config);

var cloneObj = { ...config1 };
console.log(cloneObj);

var userInput = { name: 'Bob' };
var defaults = { role: 'user', active: true };
var userRecord = { ...defaults, ...userInput };
console.log(userRecord);

var uniqueVals = Set([1, 2, 2, 3, 3, 4]);
var uniqueArr = [...uniqueVals];
console.log(uniqueArr);                  // [1, 2, 3, 4]

var entries = Map([['id', 1], ['name', 'Alice']]);
var mapEntries = [...entries];
console.log(mapEntries);

console.log(...['a', 'b', 'c']);


// ============================================================
console.log("\n=== TESTS LOU COMPLETADOS ===");

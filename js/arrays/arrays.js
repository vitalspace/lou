console.time("total");

// // Array basics
// var arr = [1, 2, 3, 4, 5];
// console.log(arr.length);
// console.log(arr.at(0));
// console.log(arr.at(-1));
// console.log(arr.at(2));

// // Bracket indexing
// console.log(arr[0]);
// console.log(arr[4]);

// // Push
// arr.push(6);
// console.log(arr.length);
// console.log(arr[5]);

// arr.push(7, 8);
// console.log(arr.length);
// console.log(arr[6]);
// console.log(arr[7]);

// Pop
// var last = arr.pop();
// console.log(last);
// console.log(arr.length);

// last = arr.pop();
// console.log(last);
// console.log(arr.length);

// Mixed types
// var mixed = [1, "hello", true, null];
// console.log(mixed.length);
// console.log(mixed[0]);
// console.log(mixed[1]);
// console.log(mixed[2]);
// console.log(mixed[3]);

// // Nested arrays
// var nested = [[1, 2], [3, 4]];
// console.log(nested.length);
// console.log(nested[0][1]);
// console.log(nested[1][0]);

// // 3x3 matrix with nested for loops
// var matrix = [[], [], []];
// for (let i = 0; i < 3; i = i + 1) {
//   for (let j = 0; j < 3; j = j + 1) {
//     matrix[i].push(i * 3 + j + 1);
//   }
// }
// console.log(matrix[0]);
// console.log(matrix[1]);
// console.log(matrix[2]);

// // Predefined matrix
// var predefined = [[1, 2, 3], [4, 5, 6], [7, 8, 9]];
// for (let i = 0; i < 3; i = i + 1) {
//   for (let j = 0; j < 3; j = j + 1) {
//     console.log(predefined[i][j]);
//   }
// }

// // Concat
// var a1 = ["a", "b", "c"];
// var a2 = ["d", "e", "f"];
// var a3 = a1.concat(a2);
// console.log(a3.length);
// console.log(a3[0]);
// console.log(a3[3]);
// console.log(a3[5]);

// // Concat with values
// var a4 = a1.concat(1, [2, 3]);
// console.log(a4.length);
// console.log(a4[0]);
// console.log(a4[3]);
// console.log(a4[4]);
// console.log(a4[5]);

// // Concat empty
// var empty = [].concat([1, 2]);
// console.log(empty.length);
// console.log(empty[0]);

// // Concat no args (copy)
// var copy = a1.concat();
// console.log(copy.length);
// console.log(copy[0]);

// // copyWithin target start end
// var cw1 = ["a", "b", "c", "d", "e"];
// console.log(cw1.copyWithin(0, 3, 4));

// // copyWithin only target (start=0)
// var cw2 = [1, 2, 3, 4, 5];
// console.log(cw2.copyWithin(2));

// // copyWithin negative indices
// var cw3 = [1, 2, 3, 4, 5];
// console.log(cw3.copyWithin(-2, -3, -1));

// // copyWithin start to end
// var cw4 = ["a", "b", "c", "d", "e"];
// console.log(cw4.copyWithin(1, 3));

// entries — using .value
// var letters = ["a", "b", "c"];
// var it = letters.entries();
// console.log(it.next().value); // [0, "a"]
// console.log(it.next().value); // [1, "b"]
// console.log(it.next().value); // [2, "c"]
// console.log(it.next().value); // undefined

// var nums = [10, 20, 30];
// var numIt = nums.entries();
// console.log(numIt.next().value); // [0, 10]
// console.log(numIt.next().value); // [1, 20]
// console.log(numIt.next().value); // [2, 30]
// console.log(numIt.next().value); // undefined

// var emptyIt = [].entries();
// console.log(emptyIt.next().value); // undefined

// var mixedIt = [1, "hello", true].entries();
// console.log(mixedIt.next().value); // [0, 1]
// console.log(mixedIt.next().value); // [1, "hello"]
// console.log(mixedIt.next().value); // [2, true]
// console.log(mixedIt.next().value); // undefined

// // entries — using .done
// var doneIt = ["x"].entries();
// console.log(doneIt.next().done); // false
// console.log(doneIt.next().done); // true

// Every
// function isBelowThreshold(currentValue) {
//   return currentValue < 40;
// }
// var every1 = [1, 30, 39, 29, 10, 13].every(isBelowThreshold);
// console.log(every1);

// var every2 = [12, 5, 8, 130, 44].every(isBelowThreshold);
// console.log(every2);

// var every3 = [].every(isBelowThreshold);
// console.log(every3);

// // Fill
// var fill_arr = [1, 2, 3, 4];
// console.log(fill_arr.fill(0, 2, 4));
// console.log(fill_arr.fill(5, 1));
// console.log(fill_arr.fill(6));

// // Fill examples from spec
// console.log([1, 2, 3].fill(4));
// console.log([1, 2, 3].fill(4, 1));
// console.log([1, 2, 3].fill(4, 1, 2));
// console.log([1, 2, 3].fill(4, 1, 1));
// console.log([1, 2, 3].fill(4, 3, 3));
// console.log([1, 2, 3].fill(4, -3, -2));
// console.log(Array(3).fill(4));

// // Fill populate empty array
// var tempGirls = Array(5).fill("girl", 0);
// console.log(tempGirls);

// // Filter
// function isBigEnough(value) {
//   return value >= 10;
// }
// var filtered = [12, 5, 8, 130, 44].filter(isBigEnough);
// console.log(filtered);

// // Filter empty
// var emptyFilter = [].filter(isBigEnough);
// console.log(emptyFilter);

// // Filter none pass
// function alwaysFalse(x) {
//   return false;
// }
// var nonePass = [1, 2, 3].filter(alwaysFalse);
// console.log(nonePass);

// // Filter with index
// function greaterThanIndex(value, index) {
//   return value > index;
// }
// var indexFilter = [0, 2, 1, 3, 2].filter(greaterThanIndex);
// console.log(indexFilter);

// Find
// function isBiggerThan10(element) {
//   return element > 10;
// }
// var found1 = [5, 12, 8, 130, 44].find(isBiggerThan10);
// console.log(found1);

// var found2 = [4, 5, 6].find(isBiggerThan10);
// console.log(found2);

// // Find with index
// function isIndexGt2(value, index) {
//   return index > 2;
// }
// var found3 = [10, 20, 30, 40, 50].find(isIndexGt2);
// console.log(found3);

// // FindIndex
// var array1 = [5, 12, 8, 130, 44];
// function isLargeNumber(element) {
//   return element > 13;
// }
// console.log(array1.findIndex(isLargeNumber)); // 3

// var noMatch = [1, 2, 3].findIndex(isLargeNumber);
// console.log(noMatch); // -1

// // FindLast
// function mayorQue45(v) {
//   return v > 45;
// }
// console.log([5, 12, 50, 130, 44].findLast(mayorQue45)); // 130
// console.log([4, 5, 6].findLast(mayorQue45)); // undefined

// // FindLast with index
// function indexMenorQue3(v, i) {
//   return i < 3;
// }
// console.log([10, 20, 30, 40, 50].findLast(indexMenorQue3)); // 30
//
// // FindLastIndex
// function esMayorQue30(v) {
//   return v > 30;
// }
// console.log([5, 12, 50, 130, 44].findLastIndex(esMayorQue30)); // 3
// console.log([1, 2, 3].findLastIndex(esMayorQue30)); // -1
//
//
// FindLastIndex with index
// function indiceMenorQue3(v, i) {
//   return i < 3;
// }
// console.log([10, 20, 30, 40, 50].findLastIndex(indiceMenorQue3)); // 2

// // FindLastIndex with inline arrow
// console.log([5, 12, 50, 130, 44].findLastIndex((x) => x > 100)); // 3

// // Flat
// var flat1 = [1, 2, [3, 4]];
// console.log(flat1.flat()); // [1, 2, 3, 4]

// var flat2 = [1, 2, [3, 4, [5, 6]]];
// console.log(flat2.flat()); // [1, 2, 3, 4, [5, 6]]
// console.log(flat2.flat(2)); // [1, 2, 3, 4, 5, 6]

// var flat3 = [1, [2, [3, [4]]]];
// console.log(flat3.flat(100)); // [1, 2, 3, 4]

// // FlatMap
// var flatMap1 = [1, 2, 3, 4];
// console.log(flatMap1.flatMap((x) => [x, x * 2]));
// // Expected: [1, 2, 2, 4, 3, 6, 4, 8]

// var parts = [[1, 2], [3], [4, 5, 6]];
// console.log(parts.flatMap((arr) => arr));
// // Expected: [1, 2, 3, 4, 5, 6]

// // FlatMap with index
// var indexed = [10, 20, 30];
// console.log(indexed.flatMap((v, i) => [v, i]));
// // Expected: [10, 0, 20, 1, 30, 2]

// // FlatMap returning non-array acts like map
// var mapped = [1, 2, 3];
// console.log(mapped.flatMap((x) => x * 10));
// // Expected: [10, 20, 30]

// // FlatMap empty array
// var empty = [].flatMap((x) => [x, x]);
// console.log(empty);
// // Expected: []

// // forEach
// var forEachArr = ["a", "b", "c"];
// function logElement(value) {
//   console.log(value);
// }
// forEachArr.forEach(logElement);
// // Expected: "a", "b", "c"

// // forEach with index
// function logElementAndIndex(value, index) {
//   console.log(value);
//   console.log(index);
// }
// ["x", "y", "z"].forEach(logElementAndIndex);
// // Expected: "x", 0, "y", 1, "z", 2

// // forEach empty array does nothing
// [].forEach(logElement);

// // Array.from string
// var fromStr = Array.from("foo");
// console.log(fromStr.length);
// console.log(fromStr[0]);
// console.log(fromStr[1]);
// console.log(fromStr[2]);
// // Expected: 3, "f", "o", "o"

// // Array.from array
// var fromArr = Array.from([1, 2, 3]);
// console.log(fromArr.length);
// console.log(fromArr[0]);
// console.log(fromArr[2]);
// // Expected: 3, 1, 3

// // Array.from with map function
// function double(x) {
//   return x + x;
// }
// var fromMapped = Array.from([1, 2, 3], double);
// console.log(fromMapped[0]);
// console.log(fromMapped[1]);
// console.log(fromMapped[2]);
// // Expected: 2, 4, 6

// // Array.isArray
// console.log(Array.isArray([1, 2, 3]));
// // Expected: true
// console.log(Array.isArray({ length: 3 }));
// // Expected: false
// console.log(Array.isArray([]));
// // Expected: true

// // includes
// var includesArr = [1, 2, 3];
// console.log(includesArr.includes(2));
// // Expected: true
// console.log(includesArr.includes(4));
// // Expected: false

// // includes with fromIndex
// var pets = ["cat", "dog", "bat"];
// console.log(pets.includes("cat"));
// // Expected: true
// console.log(pets.includes("at"));
// // Expected: false

// // indexOf
// var beasts = ["ant", "bison", "camel", "duck", "bison"];
// console.log(beasts.indexOf("bison"));
// // Expected: 1
// console.log(beasts.indexOf("bison", 2));
// // Expected: 4
// console.log(beasts.indexOf("giraffe"));
// // Expected: -1

// // Join
// var join1 = ["Fire", "Air", "Water"];
// console.log(join1.join());
// // Expected: "Fire,Air,Water"
// console.log(join1.join(", "));
// // Expected: "Fire, Air, Water"
// console.log(join1.join(" + "));
// // Expected: "Fire + Air + Water"
// console.log(join1.join(""));
// // Expected: "FireAirWater"
// console.log([1, 2, 3].join("."));
// // Expected: "1.2.3"

// // Keys
// var keysArr = ["a", "b", "c"];
// var keyIt = keysArr.keys();
// console.log(keyIt.next().value); // 0
// console.log(keyIt.next().value); // 1
// console.log(keyIt.next().value); // 2
// console.log(keyIt.next().value); // undefined

// var emptyKeys = [].keys();
// console.log(emptyKeys.next().value); // undefined

// var mixedKeys = [1, "hello", true].keys();
// console.log(mixedKeys.next().value); // 0
// console.log(mixedKeys.next().value); // 1
// console.log(mixedKeys.next().value); // 2
// console.log(mixedKeys.next().value); // undefined

// // Keys — using .done
// var doneKeys = ["x"].keys();
// console.log(doneKeys.next().done); // false
// console.log(doneKeys.next().done); // true

// // lastIndexOf
// var animals = ["Dodo", "Tiger", "Penguin", "Dodo"];
// console.log(animals.lastIndexOf("Dodo")); // 3
// console.log(animals.lastIndexOf("Dodo", 2)); // 0
// console.log(animals.lastIndexOf("giraffe")); // -1

// var numbers = [1, 2, 3, 2, 1];
// console.log(numbers.lastIndexOf(2)); // 3
// console.log(numbers.lastIndexOf(2, 2)); // 1
// console.log(numbers.lastIndexOf(5)); // -1

// // lastIndexOf with no fromIndex finds from end
// console.log([1, 2, 3, 4, 3].lastIndexOf(3)); // 4
// console.log([].lastIndexOf(1)); // -1

// // Map
// var map1 = [1, 4, 9, 16].map((x) => x * 2);
// console.log(map1); // [2, 8, 18, 32]

// var map2 = ["a", "b", "c"].map((x) => x.toUpperCase());
// console.log(map2); // ["A", "B", "C"]

// var map3 = [10, 20, 30].map((v, i) => v + i);
// console.log(map3); // [10, 21, 32]

// // Map empty
// var map4 = [].map((x) => x * 2);
// console.log(map4); // []

// // Map with named function
// function double(x) {
//   return x * 2;
// }
// var map5 = [1, 2, 3].map(double);
// console.log(map5); // [2, 4, 6]

// // Reduce
// var reduce1 = [1, 2, 3, 4].reduce(
//   (accumulator, currentValue) => accumulator + currentValue,
//   0,
// );
// console.log(reduce1); // 10

// // Reduce without initialValue
// var reduce2 = [1, 2, 3, 4].reduce(
//   (accumulator, currentValue) => accumulator + currentValue,
// );
// console.log(reduce2); // 10

// // Reduce with index
// var reduce3 = [1, 2, 3].reduce((acc, v, i) => acc + v + i, 0);
// console.log(reduce3); // 9

// // Reduce empty with initialValue
// var reduce4 = [].reduce((acc, v) => acc + v, 0);
// console.log(reduce4); // 0

// // Reduce to object
// var reduce5 = ["a", "b", "c"].reduce((acc, v, i) => {
//   acc[v] = i;
//   return acc;
// }, {});
// console.log(reduce5); // { a: 0, b: 1, c: 2 }

// === REDUCERIGHT ===
var reduceRight1 = [
  [0, 1],
  [2, 3],
  [4, 5],
].reduceRight((acc, v) => acc.concat(v));
console.log(reduceRight1); // [4, 5, 2, 3, 0, 1]

// reduceRight with initialValue
var reduceRight2 = [1, 2, 3, 4].reduceRight((acc, v) => acc + v, 0);
console.log(reduceRight2); // 10

// reduceRight without initialValue
var reduceRight3 = [1, 2, 3, 4].reduceRight((acc, v) => acc + v);
console.log(reduceRight3); // 10

// reduceRight flattens right to left
var nested = [
  [0, 1],
  [2, 3],
  [4, 5],
];
var flatRight = nested.reduceRight((acc, v) => acc.concat(v));
console.log(flatRight); // [4, 5, 2, 3, 0, 1]

// reduceRight empty with initialValue
var reduceRight4 = [].reduceRight((acc, v) => acc + v, 0);
console.log(reduceRight4); // 0

// === REVERSE ===
var reverse1 = ["one", "two", "three"];
console.log("array1:", reverse1); // ["one", "two", "three"]
var reversed = reverse1.reverse();
console.log("reversed:", reversed); // ["three", "two", "one"]
console.log("array1:", reverse1); // ["three", "two", "one"]

// Reverse numbers
var numsRev = [1, 2, 3, 4, 5];
console.log(numsRev.reverse()); // [5, 4, 3, 2, 1]

// Reverse single element
var single = [42];
console.log(single.reverse()); // [42]

// Reverse empty
var emptyRev = [];
console.log(emptyRev.reverse()); // []

// Reverse mixed types
var mixedRev = [1, "hello", true];
console.log(mixedRev.reverse()); // [true, "hello", 1]

// === SHIFT ===
var shift1 = [1, 2, 3];
var firstElement = shift1.shift();
console.log(shift1); // [2, 3]
console.log(firstElement); // 1

// Shift empty returns undefined
var shiftEmpty = [];
console.log(shiftEmpty.shift()); // undefined

// Shift single element
var shiftSingle = [99];
console.log(shiftSingle.shift()); // 99
console.log(shiftSingle.length); // 0

// Shift multiple times
var shiftMulti = ["a", "b", "c", "d"];
console.log(shiftMulti.shift()); // "a"
console.log(shiftMulti.shift()); // "b"
console.log(shiftMulti.length); // 2

// Shift mixed types
var shiftMixed = [1, "hello", true];
console.log(shiftMixed.shift()); // 1
console.log(shiftMixed.length); // 2

// === SLICE ===
var animals = ["ant", "bison", "camel", "duck", "elephant"];
console.log(animals.slice(2)); // ["camel", "duck", "elephant"]
console.log(animals.slice(2, 4)); // ["camel", "duck"]
console.log(animals.slice(1, 5)); // ["bison", "camel", "duck", "elephant"]

// Slice no args (copy)
var sliceCopy = animals.slice();
console.log(sliceCopy); // ["ant", "bison", "camel", "duck", "elephant"]
console.log(sliceCopy === animals); // false

// Slice negative start
console.log(animals.slice(-2)); // ["duck", "elephant"]
console.log(animals.slice(-3, -1)); // ["camel", "duck"]

// Slice start > length returns empty
console.log(animals.slice(10)); // []

// Slice with 0 start
console.log(animals.slice(0)); // ["ant", "bison", "camel", "duck", "elephant"]

// Slice empty array
console.log([].slice(0, 2)); // []

// Slice numbers
var numsSlice = [10, 20, 30, 40, 50];
console.log(numsSlice.slice(1, 3)); // [20, 30]
console.log(numsSlice.slice(0, 0)); // []

// === SOME ===
function even(v) {
  return v % 2 === 0;
}
console.log([1, 2, 3, 4, 5].some(even)); // true

// Some none match
console.log([1, 3, 5, 7].some(even)); // false

// Some empty always false
console.log([].some(even)); // false

// Some with index
function indexGt3(v, i) {
  return i > 3;
}
console.log([10, 20, 30, 40, 50].some(indexGt3)); // true

// === SORT ===
var months = ["March", "Jan", "Nov", "Jan"];
console.log(months.sort()); // ["Jan", "Jan", "March", "Nov"]

// Sort numbers (converted to strings)
var numsSort = [1, 30, 4, 21, 100000];
console.log(numsSort.sort()); // [1, 100000, 21, 30, 4]

// Sort with compare function
var numsSort2 = [1, 30, 4, 21, 100000];
console.log(numsSort2.sort((a, b) => a - b)); // [1, 4, 21, 30, 100000]

// Sort descending
var numsSort3 = [1, 30, 4, 21, 100000];
console.log(numsSort3.sort((a, b) => b - a)); // [100000, 30, 21, 4, 1]

// Sort strings default
var words = ["banana", "apple", "cherry", "date"];
console.log(words.sort()); // ["apple", "banana", "cherry", "date"]

// === SPLICE ===
var months2 = ["Jan", "March", "April", "June"];
months2.splice(1, 0, "Feb");
console.log(months2); // ["Jan", "Feb", "March", "April", "June"]

// Splice remove 1 at index 4 and add "May"
months2.splice(4, 1, "May");
console.log(months2); // ["Jan", "Feb", "March", "April", "May"]

// Splice delete only
var spliceDel = ["a", "b", "c", "d"];
console.log(spliceDel.splice(1, 2)); // ["b", "c"]
console.log(spliceDel); // ["a", "d"]

// Splice insert without delete
var spliceIns = ["a", "c"];
spliceIns.splice(1, 0, "b");
console.log(spliceIns); // ["a", "b", "c"]

// Splice negative start
var spliceNeg = ["a", "b", "c", "d"];
console.log(spliceNeg.splice(-2, 1)); // ["c"]
console.log(spliceNeg); // ["a", "b", "d"]

// === TOSTRING ===
console.log([1, 2, "a", "1a"].toString()); // "1,2,a,1a"
console.log([1, 2, 3].toString()); // "1,2,3"
console.log([].toString()); // ""
console.log([true, false].toString()); // "true,false"
console.log([null, undefined].toString()); // ","

// === UNSHIFT ===
var unshift1 = [1, 2, 3];
console.log(unshift1.unshift(4, 5)); // 5
console.log(unshift1); // [4, 5, 1, 2, 3]

// Unshift one element
var unshift2 = ["b", "c"];
console.log(unshift2.unshift("a")); // 3
console.log(unshift2); // ["a", "b", "c"]

// Unshift empty array
var unshift3 = [];
console.log(unshift3.unshift(1)); // 1
console.log(unshift3); // [1]

// Unshift multiple types
var unshift4 = [2, 3];
console.log(unshift4.unshift(true, "a")); // 4
console.log(unshift4); // [true, "a", 2, 3]

// === VALUES ===
var valuesArr = ["a", "b", "c"];
var valIt = valuesArr.values();
console.log(valIt.next().value); // "a"
console.log(valIt.next().value); // "b"
console.log(valIt.next().value); // "c"
console.log(valIt.next().value); // undefined

// Values empty
var emptyIt = [].values();
console.log(emptyIt.next().value); // undefined

// Values done
var doneIt = ["x"].values();
console.log(doneIt.next().done); // false
console.log(doneIt.next().done); // true

// === WITH ===
console.log([1, 2, 3, 4, 5].with(2, 6)); // [1, 2, 6, 4, 5]

// With negative index
console.log([1, 2, 3, 4, 5].with(-1, 10)); // [1, 2, 3, 4, 10]

// With does not mutate original
var withOrig = [1, 2, 3];
var withNew = withOrig.with(0, 99);
console.log(withNew); // [99, 2, 3]
console.log(withOrig); // [1, 2, 3]

// With index 0
console.log([10, 20, 30].with(0, 100)); // [100, 20, 30]

// With string value replacement
console.log(["a", "b", "c"].with(1, "z")); // ["a", "z", "c"]

console.timeEnd("total");

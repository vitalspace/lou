// BigInt-aware Array methods
// Array methods should distinguish BigInt from Number when comparing and
// include BigInts when sorting (via String() conversion, like Node.js).
//
// Spec: specs/todos/hechos/bigint-array-methods.md

const arr = [5n, 1n, 3n, 2n, 4n];
arr.sort();
console.log(arr);

const arr2 = [1n, 2n, 3n, 2n];
console.log(arr2.indexOf(2n));
console.log(arr2.lastIndexOf(2n));
console.log(arr2.includes(2n));
console.log(arr2.indexOf(2));

// Mix con Number: deben distinguir tipos
const arr3 = [1, 2, 1n, 2n];
console.log(arr3.indexOf(1));
console.log(arr3.indexOf(1n));
console.log(arr3.includes(1n));
console.log(arr3.includes(1));

// BigInt zero y negativos
const arr4 = [0n, -1n, 0n, 5n];
console.log(arr4.indexOf(0n));
console.log(arr4.lastIndexOf(0n));
console.log(arr4.includes(-1n));
console.log(arr4.includes(-99n));

// BigInt grandes (> i64)
const huge = 2n ** 100n;
const arr5 = [huge, 1n, huge];
console.log(arr5.indexOf(huge));
console.log(arr5.lastIndexOf(huge));
console.log(arr5.includes(huge));
console.log(arr5.includes(2n));

// find / findIndex / findLast / findLastIndex con BigInt via ===
const arr6 = [10n, 20n, 30n];
console.log(arr6.find(x => x === 20n));
console.log(arr6.findIndex(x => x === 20n));
console.log(arr6.findLast(x => x === 20n));
console.log(arr6.findLastIndex(x => x === 20n));
console.log(arr6.findIndex(x => x === 99n));

// toSorted preserva BigInt
const sortedCopy = arr6.toSorted();
console.log(sortedCopy);

// sort con callback y BigInt
const arr7 = [3n, 1n, 2n];
arr7.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
console.log(arr7);

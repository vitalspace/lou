// BigInt as array index
// arr[1n] should work the same as arr[1]. Out-of-range / negative BigInt
// indices return undefined (Node.js semantics).
//
// Spec: specs/todos/hechos/bigint-array-index.md

const arr = [10, 20, 30, 40];
console.log(arr[0n]);
console.log(arr[1n]);
console.log(arr[3n]);

arr[1n] = 200;
console.log(arr[1]);

const arr2 = [1n, 2n, 3n];
arr2[0n] = 100n;
console.log(arr2[0]);

// Round-trip: integer and BigInt index return the same element
const a = [10, 20, 30];
console.log(a[1n]);
a[1n] = 200;
console.log(a[1]);
console.log(a[1n]);

// BigInt too large to fit in i64 → undefined
const huge = 2n ** 100n;
console.log(a[huge]);

// Negative BigInt → undefined
console.log(a[-1n]);

// In-range BigInt but past the end → undefined
console.log(a[100n]);

// BigInt assignment to a new index extends the array with holes
const b = [1, 2, 3];
b[5n] = 99;
console.log(b[5]);
console.log(b.length);

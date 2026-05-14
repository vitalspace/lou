// Array basics
var arr = [1, 2, 3, 4, 5];
console.log(arr.length);
console.log(arr.at(0));
console.log(arr.at(-1));
console.log(arr.at(2));

// Bracket indexing
console.log(arr[0]);
console.log(arr[4]);

// Push
arr.push(6);
console.log(arr.length);
console.log(arr[5]);

arr.push(7, 8);
console.log(arr.length);
console.log(arr[6]);
console.log(arr[7]);

// Pop
var last = arr.pop();
console.log(last);
console.log(arr.length);

last = arr.pop();
console.log(last);
console.log(arr.length);

// Mixed types
var mixed = [1, "hello", true, null];
console.log(mixed.length);
console.log(mixed[0]);
console.log(mixed[1]);
console.log(mixed[2]);
console.log(mixed[3]);

// Nested arrays
var nested = [[1, 2], [3, 4]];
console.log(nested.length);
console.log(nested[0][1]);
console.log(nested[1][0]);

// 3x3 matrix with nested for loops
var matrix = [[], [], []];
for (let i = 0; i < 3; i = i + 1) {
  for (let j = 0; j < 3; j = j + 1) {
    matrix[i].push(i * 3 + j + 1);
  }
}
console.log(matrix[0]);
console.log(matrix[1]);
console.log(matrix[2]);

// Predefined matrix
var predefined = [[1, 2, 3], [4, 5, 6], [7, 8, 9]];
for (let i = 0; i < 3; i = i + 1) {
  for (let j = 0; j < 3; j = j + 1) {
    console.log(predefined[i][j]);
  }
}

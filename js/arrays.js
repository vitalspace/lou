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

// Concat
var a1 = ["a", "b", "c"];
var a2 = ["d", "e", "f"];
var a3 = a1.concat(a2);
console.log(a3.length);
console.log(a3[0]);
console.log(a3[3]);
console.log(a3[5]);

// Concat with values
var a4 = a1.concat(1, [2, 3]);
console.log(a4.length);
console.log(a4[0]);
console.log(a4[3]);
console.log(a4[4]);
console.log(a4[5]);

// Concat empty
var empty = [].concat([1, 2]);
console.log(empty.length);
console.log(empty[0]);

// Concat no args (copy)
var copy = a1.concat();
console.log(copy.length);
console.log(copy[0]);

// copyWithin target start end
var cw1 = ["a", "b", "c", "d", "e"];
console.log(cw1.copyWithin(0, 3, 4));

// copyWithin only target (start=0)
var cw2 = [1, 2, 3, 4, 5];
console.log(cw2.copyWithin(2));

// copyWithin negative indices
var cw3 = [1, 2, 3, 4, 5];
console.log(cw3.copyWithin(-2, -3, -1));

// copyWithin start to end
var cw4 = ["a", "b", "c", "d", "e"];
console.log(cw4.copyWithin(1, 3));

// entries
var letters = ["a", "b", "c"];
var it = letters.entries();
console.log(it.next());
console.log(it.next());
console.log(it.next());
console.log(it.next());

var nums = [10, 20, 30];
var numIt = nums.entries();
console.log(numIt.next());
console.log(numIt.next());
console.log(numIt.next());
console.log(numIt.next());

var emptyIt = [].entries();
console.log(emptyIt.next());

var mixedIt = [1, "hello", true].entries();
console.log(mixedIt.next());
console.log(mixedIt.next());
console.log(mixedIt.next());
console.log(mixedIt.next());

// Every
function isBelowThreshold(currentValue) {
  return currentValue < 40;
}
var every1 = [1, 30, 39, 29, 10, 13].every(isBelowThreshold);
console.log(every1);

var every2 = [12, 5, 8, 130, 44].every(isBelowThreshold);
console.log(every2);

var every3 = [].every(isBelowThreshold);
console.log(every3);

// DEBUG
console.log("HERE");

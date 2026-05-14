// Array builtins tests
var arr = [1, 2, 3];

// length
console.log(arr.length);

// push
console.log(arr.push(4));
console.log(arr.push(5, 6));

// at (positive index)
console.log(arr.at(0));
console.log(arr.at(2));

// at (negative index)
console.log(arr.at(-1));
console.log(arr.at(-3));

// pop
console.log(arr.pop());
console.log(arr.pop());

// copyWithin
var arr2 = ["a", "b", "c", "d", "e"];
console.log(arr2.copyWithin(0, 3, 4));
console.log(arr2.copyWithin(1, 3));

// copyWithin negative indices
var arr3 = [1, 2, 3, 4, 5];
console.log(arr3.copyWithin(-2, -3, -1));

// copyWithin default start=0
var arr4 = [1, 2, 3, 4, 5];
console.log(arr4.copyWithin(2));

// verify final state
console.log(arr.length);
console.log(arr.at(0));

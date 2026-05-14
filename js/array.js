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

// verify final state
console.log(arr.length);
console.log(arr.at(0));

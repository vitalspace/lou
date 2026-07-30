// Non-callable TypeError test - simplified version
// Both Lou and Node should produce identical output

// Map.size is a getter property
var m = new Map();
m.set("a", 1);
console.log(m.size);

// Set.size is a getter property
var s = new Set();
s.add(1);
console.log(s.size);

// Array.length is a property
var arr = [1, 2, 3];
console.log(arr.length);

// String.length is a property
var str = "hi";
console.log(str.length);

// Plain object property access
var obj = {};
obj.x = 10;
console.log(obj.x);

// Actual methods still work
var m2 = new Map();
m2.set("a", 99);
console.log(m2.get("a"));

var arr2 = [1, 2];
arr2.push(3);
console.log(arr2.length);

console.log("DONE");

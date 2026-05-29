// === Set tests ===
console.log("=== Set ===");

var s = Set();
console.log(s.size);

s.add(1);
s.add(2);
s.add(3);
s.add(2); // duplicate
console.log(s.size);
console.log(s.has(1));
console.log(s.has(4));

s.delete(2);
console.log(s.size);
console.log(s.has(2));

// Array.from with Set
console.log("=== Array.from(Set) ===");
var s2 = Set();
s2.add(10);
s2.add(20);
s2.add(30);
var arr = Array.from(s2);
console.log(arr);

// Set from array
console.log("=== Set from array ===");
var s3 = Set([1, 2, 3, 2, 1]);
console.log(s3.size);

// Set forEach
console.log("=== Set forEach ===");
var result = [];
s3.forEach(function(v) { result.push(v); });
console.log(result);

// === Map tests ===
console.log("\n=== Map ===");
var m = Map();
console.log(m.size);

m.set("a", 1);
m.set("b", 2);
m.set("c", 3);
m.set("b", 4); // update
console.log(m.size);
console.log(m.get("a"));
console.log(m.get("b"));
console.log(m.get("d"));

m.delete("a");
console.log(m.size);
console.log(m.has("a"));
console.log(m.has("b"));

// Array.from with Map
console.log("=== Array.from(Map) ===");
var m2 = Map();
m2.set("x", 10);
m2.set("y", 20);
var arr2 = Array.from(m2);
console.log(arr2);

// Map from array
console.log("=== Map from array ===");
var m3 = Map([["a", 1], ["b", 2]]);
console.log(m3.size);
console.log(m3.get("a"));
console.log(m3.get("b"));

// Map forEach
console.log("=== Map forEach ===");
var mapResult = [];
m3.forEach(function(val, key) { mapResult.push(key + ":" + val); });
console.log(mapResult);

console.log("\n=== DONE ===");
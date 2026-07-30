// delete operator tests
// Delete property from object
const obj = { a: 1, b: 2, c: 3 };
delete obj.b;
console.log(obj);

// Delete index from array
const arr = [1, 2, 3, 4];
delete arr[1];
console.log(arr);
console.log(arr.length);

// Delete with chained access
const nested = { a: { b: { c: 1 } } };
delete nested.a.b.c;
console.log(nested.a.b);

// Delete returns boolean
const obj2 = { x: 1 };
console.log(delete obj2.x);
console.log(delete obj2.x);

// Delete nonexistent property returns true
const obj3 = {};
console.log(delete obj3.missing);

// Bracket notation on object
const obj4 = { email: "a@b.com" };
console.log(delete obj4["email"]);
console.log(obj4);

// Bracket notation with variable key
const obj5 = { name: "Alice", age: 30, city: "NYC" };
const key = "age";
console.log(delete obj5[key]);
console.log(obj5);

// Bracket notation on nonexistent key
const obj6 = { a: 1 };
console.log(delete obj6["b"]);
console.log(obj6);

// Mixed dot and bracket notation
const obj7 = { x: { y: 10 } };
console.log(delete obj7["x"]["y"]);
console.log(obj7.x);

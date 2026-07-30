// Unicode identifiers in source code

// Latin accented
var café = "coffee";
var naïve = true;
var résumé = "CV";
console.log(café, naïve, résumé);

// Greek
var π = 3.14159;
var Σ = function(arr) { return arr.reduce(function(a, b) { return a + b; }, 0); };
console.log(π, Σ([1, 2, 3, 4]));

// CJK
var 名前 = "Alice";
var 変数 = 42;
var 世界 = "world";
console.log(名前, 変数, 世界);

// Mixed: Greek letter + ASCII suffix
var λbegin = "start";
var endλ = "end";
console.log(λbegin, endλ);

// Identifier with digits after unicode letter
var π1 = "pi-one";
var 変数42 = 4242;
console.log(π1, 変数42);

// Unicode identifiers in function definitions and parameters
const greet = (名前) => "Hello, " + 名前;
console.log(greet("Bob"));

// Unicode as object property keys and access
const obj = { café: "x", 名前: "Alice", π: 3.14 };
console.log(obj.café, obj.名前, obj.π);

// typeof for unicode identifiers
console.log(typeof π, typeof café, typeof 変数);

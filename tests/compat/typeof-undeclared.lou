// typeof on undeclared variables returns "undefined" without throwing
console.log(typeof undeclaredVar);     // "undefined"
console.log(typeof anotherMissing);    // "undefined"
console.log(typeof notHere);           // "undefined"

// typeof on declared variables still works normally
var x = 42;
console.log(typeof x);                 // "number"
var s = "hello";
console.log(typeof s);                 // "string"

// typeof on expressions (all declared vars here)
console.log(typeof (x + 1));           // "number"

// typeof on function
function f() { return 1; }
console.log(typeof f);                 // "function"

// typeof null
console.log(typeof null);              // "object"

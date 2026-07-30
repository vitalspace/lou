// Regex literal syntax: /pattern/flags
// Tests lexer tokenization and division disambiguation

console.log("--- regex literal syntax ---");
console.log(typeof /hello/);
console.log(typeof /hello/gi);

console.log("--- regex literal vs division ---");
const a = 6;
const b = 3;
console.log(a / b);  // division, not regex

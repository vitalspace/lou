// Minimal debug test for for...of
var sum = 0;
for (const x of [1, 2, 3]) {
  sum = sum + x;
}
console.log(sum);

var arr = [10, 20];
var result = [];
for (var v of arr) {
  result.push(v);
}
console.log(result);

// String iteration
var chars = [];
for (const c of "ab") {
  chars.push(c);
}
console.log(chars);

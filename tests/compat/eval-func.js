console.log(eval("2 + 2"));
var x = 10;
console.log(eval("x"));
console.log(eval("var z = 100; z"));
console.log(typeof z);
console.log(eval("let q = 7; q"));
console.log(typeof q);
try {
  eval("throw new Error(\"boom\")");
} catch (e) {
  console.log(e.message);
}
try {
  eval("let =");
} catch (e) {
  console.log(e.name);
}
var fn = eval("(function (a) { return a * 3; })");
console.log(fn(4));

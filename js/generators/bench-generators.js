// Benchmark: generators, yield*, spread, for...of

function* range(start, end) {
  while (start < end) {
    yield start;
    start = start + 1;
  }
}

function* fib(n) {
  var a = 0; var b = 1; var i = 0;
  while (i < n) {
    yield a;
    var next = a + b;
    a = b;
    b = next;
    i = i + 1;
  }
}

function* flatten(arrs) {
  for (var i = 0; i < arrs.length; i = i + 1) {
    yield* arrs[i];
  }
}

function* take(gen, n) {
  var count = 0;
  for (var x of gen) {
    if (count >= n) return;
    yield x;
    count = count + 1;
  }
}

// 1. Spread + yield* chain
var result1 = [];
var chained = take(flatten([range(0, 50), range(100, 150)]), 30);
for (var v of chained) {
  result1.push(v);
}

// 2. Nested yield* + for...of
function* level3() { yield* range(0, 10); }
function* level2() { yield* level3(); }
function* level1() { yield* level2(); }

var result2 = 0;
for (var x of level1()) {
  result2 = result2 + 1;
}

// 3. Many generators via spread
function* counter() {
  var i = 0;
  while (i < 100) {
    yield i;
    i = i + 1;
  }
}
var result3 = [];
for (var j = 0; j < 20; j = j + 1) {
  var spread = [...counter()];
  for (var k = 0; k < spread.length; k = k + 1) {
    result3.push(spread[k]);
  }
}

// 4. Fibonacci via for...of
var result4 = 0;
for (var x of fib(100)) {
  result4 = result4 + x;
}

// 5. Nested for...of with generators
function* chain() {
  for (var i = 0; i < 10; i = i + 1) {
    yield* range(0, i);
  }
}
var result5 = 0;
for (var x of chain()) {
  result5 = result5 + x;
}

// 6. yield* with strings
function* chars(s) {
  yield* s;
}
var result6 = 0;
for (var ch of chars("abcdefghijklmnopqrstuvwxyz")) {
  result6 = result6 + 1;
}

// 7. Abandoned generators
function* leakCheck() {
  yield 1; yield 2; yield 3; yield 4; yield 5;
}
var result7 = 0;
for (var i = 0; i < 100; i = i + 1) {
  var g = leakCheck();
  g.next();
  g.next();
}

// 8. Spread with function call
function sum(a, b, c, d, e) {
  return a + b + c + d + e;
}
var result8 = 0;
for (var i = 0; i < 50; i = i + 1) {
  result8 = result8 + sum(...range(i, i + 5));
}

// 9. yield* with arrays
function* fromArrays() {
  yield* [1, 2, 3];
  yield* [4, 5, 6];
  yield* [7, 8, 9];
}
var result9 = 0;
for (var x of fromArrays()) {
  result9 = result9 + x;
}

// 10. Interleaved generators
function* genA() { yield* range(0, 20); }
function* genB() { yield* range(100, 120); }
var result10 = 0;
var ga = genA();
var gb = genB();
for (var i = 0; i < 20; i = i + 1) {
  result10 = result10 + ga.next().value;
  result10 = result10 + gb.next().value;
}

console.log(result1.length);
console.log(result2);
console.log(result3.length);
console.log(result4);
console.log(result5);
console.log(result6);
console.log(result7);
console.log(result8);
console.log(result9);
console.log(result10);

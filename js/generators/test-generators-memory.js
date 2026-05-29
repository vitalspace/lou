// === GENERATOR MEMORY CLEANUP TESTS ===

// 1. Many generators consumed to completion
function* simpleCounter(n) {
  var i = 0;
  while (i < n) {
    yield i;
    i = i + 1;
  }
}
for (var j = 0; j < 100; j = j + 1) {
  var g = simpleCounter(5);
  while (!g.next().done) {}
}
console.log("1: many generators consumed OK");

// 2. Generators abandoned mid-yield
function* leakyGen() {
  yield 1;
  yield 2;
  yield 3;
}
for (var j = 0; j < 100; j = j + 1) {
  var g = leakyGen();
  g.next();
}
console.log("2: abandoned generators OK");

// 3. Nested generators
function* innerGen() {
  yield "inner";
}
function* outerGen() {
  var g = innerGen();
  yield g.next().value;
  yield g.next().done;
}
for (var j = 0; j < 50; j = j + 1) {
  var g = outerGen();
  while (!g.next().done) {}
}
console.log("3: nested generators OK");

// 4. Generator yielding objects
function* objectGen() {
  var obj = {};
  obj.a = 1;
  obj.b = 2;
  yield obj;
}
for (var j = 0; j < 50; j = j + 1) {
  var g = objectGen();
  var val = g.next().value;
  val.a = val.a + 1;
  g.next();
}
console.log("4: object generators OK");

// 5. Generator with early return
function* earlyReturnGen() {
  yield 1;
  return "early";
  yield 2;
}
for (var j = 0; j < 50; j = j + 1) {
  var g = earlyReturnGen();
  while (!g.next().done) {}
}
console.log("5: early return generators OK");

// 6. Multiple interleaved generators
function* range(a, b) {
  while (a < b) {
    yield a;
    a = a + 1;
  }
}
for (var j = 0; j < 50; j = j + 1) {
  var a = range(0, 3);
  var b = range(10, 13);
  a.next(); b.next(); a.next(); b.next();
  while (!a.next().done) {}
  while (!b.next().done) {}
}
console.log("6: interleaved generators OK");

// 7. Generator with many yields (stress)
function* manyYields(n) {
  var i = 0;
  while (i < n) {
    yield i;
    i = i + 1;
  }
}
for (var j = 0; j < 20; j = j + 1) {
  var g = manyYields(100);
  while (!g.next().done) {}
}
console.log("7: stress test OK");

// 8. Generator in function scope
function makeGenerator() {
  function* gen() {
    yield 42;
    yield 99;
  }
  return gen();
}
for (var j = 0; j < 50; j = j + 1) {
  var g = makeGenerator();
  while (!g.next().done) {}
}
console.log("8: function-scoped generators OK");

// 9. Generator yielding arrays
function* arrayGen() {
  var arr = [1, 2, 3];
  yield arr;
}
for (var j = 0; j < 50; j = j + 1) {
  var g = arrayGen();
  var v = g.next().value;
  v.push(4);
  g.next();
}
console.log("9: array generators OK");

// 10. Generator calling another generator
function* subGen() {
  yield "sub1";
  yield "sub2";
}
function* mainGen() {
  var sub = subGen();
  yield sub.next().value;
  yield sub.next().value;
}
for (var j = 0; j < 50; j = j + 1) {
  var g = mainGen();
  while (!g.next().done) {}
}
console.log("10: generator calling generator OK");

// 11. Deeply nested loops with yield
function* deepLoops(n) {
  for (var i = 0; i < n; i = i + 1) {
    for (var j = 0; j < n; j = j + 1) {
      yield i * n + j;
    }
  }
}
for (var j = 0; j < 20; j = j + 1) {
  var g = deepLoops(5);
  while (!g.next().done) {}
}
console.log("11: nested loops with yield OK");

// 12. Generator inside if/else
function* conditionalGen(flag) {
  if (flag) {
    yield "yes";
  } else {
    yield "no";
  }
  yield "always";
}
for (var j = 0; j < 30; j = j + 1) {
  var g = conditionalGen(j % 2 == 0);
  while (!g.next().done) {}
}
console.log("12: conditional generators OK");

console.log("ALL GENERATOR MEMORY TESTS PASSED");

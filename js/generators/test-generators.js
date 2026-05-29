// === GENERATOR TESTS ===

// 1. Simple yield (no loop)
function* simpleGen() {
  yield 42;
}
var g = simpleGen();
var step1 = g.next();
console.log(step1.value); // 42
console.log(step1.done); // false
var step2 = g.next();
console.log(step2.value); // undefined
console.log(step2.done); // true

// 2. Multiple yields
function* multiGen() {
  yield "a";
  yield "b";
  yield "c";
}
var mg = multiGen();
console.log(mg.next().value); // "a"
console.log(mg.next().value); // "b"
console.log(mg.next().value); // "c"
console.log(mg.next().done); // true

// 3. Yield inside while loop
function* countUp(n) {
  var i = 0;
  while (i < n) {
    yield i;
    i = i + 1;
  }
}
var cu = countUp(3);
console.log(cu.next().value); // 0
console.log(cu.next().value); // 1
console.log(cu.next().value); // 2
console.log(cu.next().done); // true

// 4. Yield inside for loop
function* forCount(n) {
  for (var i = 0; i < n; i = i + 1) {
    yield i;
  }
}
var fc = forCount(3);
console.log(fc.next().value); // 0
console.log(fc.next().value); // 1
console.log(fc.next().value); // 2
console.log(fc.next().done); // true

// 5. Accumulate yields via for...of
var sum = 0;
for (const x of countUp(4)) {
  sum = sum + x;
}
console.log(sum); // 6

// 6. Collect yields into array
function* range(start, end) {
  while (start < end) {
    yield start;
    start = start + 1;
  }
}
var collected = [];
for (const val of range(1, 4)) {
  collected.push(val);
}
console.log(collected); // [1, 2, 3]

// 7. Generator with early return
function* genWithReturn() {
  yield 1;
  yield 2;
  return "done early";
  yield 3;
}
var gr = genWithReturn();
console.log(gr.next().value); // 1
console.log(gr.next().value); // 2
console.log(gr.next().value); // "done early"
console.log(gr.next().done); // true

// 8. Generator with no yields (empty generator)
function* emptyGen() {
  // nothing
}
var eg = emptyGen();
console.log(eg.next().done); // true

// 9. Generator yielding undefined
function* yieldUndef() {
  yield;
  yield undefined;
}
var yu = yieldUndef();
console.log(yu.next().value); // undefined
console.log(yu.next().value); // undefined
console.log(yu.next().done); // true

// 10. Multiple generators interleaved
function* makeGen(label, start, end) {
  var i = start;
  while (i < end) {
    yield label + ":" + i;
    i = i + 1;
  }
}
var genA = makeGen("A", 0, 2);
var genB = makeGen("B", 10, 12);
console.log(genA.next().value); // "A:0"
console.log(genB.next().value); // "B:10"
console.log(genA.next().value); // "A:1"
console.log(genB.next().value); // "B:11"
console.log(genA.next().done); // true
console.log(genB.next().done); // true

// 11. Multiplication table (increment before yield to work with generator re-entry from block top)
function* multiplicationTable(limit) {
  var i = 1;
  while (i <= limit) {
    var j = 1;
    while (j <= limit) {
      yield i * j;
      j = j + 1;
    }
    i = i + 1;
  }
}
var mt = multiplicationTable(2);
console.log(mt.next().value); // 1 (1*1)
console.log(mt.next().value); // 2 (1*2)
console.log(mt.next().value); // 2 (2*1)
console.log(mt.next().value); // 4 (2*2)
console.log(mt.next().done); // true

// 12. Fibonacci generator
function* fibonacci(n) {
  var a = 0;
  var b = 1;
  var count = 0;
  while (count < n) {
    yield a;
    var next = a + b;
    a = b;
    b = next;
    count = count + 1;
  }
}
var fib = fibonacci(5);
var fibResult = [];
for (const v of fib) {
  fibResult.push(v);
}
console.log(fibResult); // [0, 1, 1, 2, 3]

// 13. Generator with if/else inside loop
function* fizzBuzz(n) {
  for (var i = 1; i <= n; i = i + 1) {
    if (i % 15 == 0) {
      yield "FizzBuzz";
    } else if (i % 3 == 0) {
      yield "Fizz";
    } else if (i % 5 == 0) {
      yield "Buzz";
    } else {
      yield i;
    }
  }
}
var fb = fizzBuzz(5);
console.log(fb.next().value); // 1
console.log(fb.next().value); // 2
console.log(fb.next().value); // "Fizz"
console.log(fb.next().value); // 4
console.log(fb.next().value); // "Buzz"
console.log(fb.next().done); // true

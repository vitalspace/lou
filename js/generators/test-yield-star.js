// === yield* GENERATOR DELEGATION TESTS ===

// 1. Simple yield* delegation
function* inner() {
  yield 1;
  yield 2;
  yield 3;
}
function* outer() {
  yield* inner();
}
var g = outer();
console.log(g.next().value); // 1
console.log(g.next().value); // 2
console.log(g.next().value); // 3
console.log(g.next().done); // true

// 2. yield* with regular yields mixed
function* mixed() {
  yield "a";
  yield* inner();
  yield "b";
}
var gm = mixed();
console.log(gm.next().value); // "a"
console.log(gm.next().value); // 1
console.log(gm.next().value); // 2
console.log(gm.next().value); // 3
console.log(gm.next().value); // "b"
console.log(gm.next().done); // true

// 3. yield* multiple delegations
function* multiDelegate() {
  yield "start";
  yield* inner();
  yield "middle";
  yield* inner();
  yield "end";
}
var gmd = multiDelegate();
console.log(gmd.next().value); // "start"
console.log(gmd.next().value); // 1
console.log(gmd.next().value); // 2
console.log(gmd.next().value); // 3
console.log(gmd.next().value); // "middle"
console.log(gmd.next().value); // 1
console.log(gmd.next().value); // 2
console.log(gmd.next().value); // 3
console.log(gmd.next().value); // "end"
console.log(gmd.next().done); // true

// 4. yield* with countUp generator (for...of loop)
function* countUp(n) {
  var i = 0;
  while (i < n) {
    yield i;
    i = i + 1;
  }
}
function* delegateCount() {
  yield* countUp(4);
}
var gdc = delegateCount();
var sum = 0;
for (const v of gdc) {
  sum = sum + v;
}
console.log(sum); // 6 (0+1+2+3)

// 5. yield* inside for...of with arrays (yield* over array)
function* flatten(arrays) {
  for (const arr of arrays) {
    yield* arr;
  }
}
var data = [[1, 2], [3, 4], [5]];
var flat = [];
for (const v of flatten(data)) {
  flat.push(v);
}
console.log(flat); // [1, 2, 3, 4, 5]

// 6. Nested yield* (chain of generators)
function* genA() {
  yield 1;
}
function* genB() {
  yield* genA();
  yield 2;
}
function* genC() {
  yield* genB();
  yield 3;
}
var gc = genC();
console.log(gc.next().value); // 1
console.log(gc.next().value); // 2
console.log(gc.next().value); // 3
console.log(gc.next().done); // true

// === ANONYMOUS function* EXPRESSION TESTS ===

// 7. Anonymous generator assigned to variable
var anonGen = function* () {
  yield "anon";
  yield 42;
};
var ag = anonGen();
console.log(ag.next().value); // "anon"
console.log(ag.next().value); // 42
console.log(ag.next().done); // true

// 8. Anonymous generator as argument
function collectValues(genFunc) {
  var gen = genFunc();
  var result = [];
  for (const v of gen) {
    result.push(v);
  }
  return result;
}
var collected = collectValues(function* () {
  yield 10;
  yield 20;
  yield 30;
});
console.log(collected); // [10, 20, 30]

// 9. Anonymous generator in object
var obj = {
  myGen: function* () {
    yield "x";
    yield "y";
  }
};
var og = obj.myGen();
console.log(og.next().value); // "x"
console.log(og.next().value); // "y"
console.log(og.next().done); // true

// 10. yield* with anonymous generator via parenthesized expression
function* useAnon() {
  yield* (function* () {
    yield 100;
    yield 200;
  })();
}
var ua = useAnon();
console.log(ua.next().value); // 100
console.log(ua.next().value); // 200
console.log(ua.next().done); // true

// 11. Direct array yield* (outside a loop)
function* yieldArray() {
  yield* [10, 20, 30];
}
var ya = yieldArray();
console.log(ya.next().value); // 10
console.log(ya.next().value); // 20
console.log(ya.next().value); // 30
console.log(ya.next().done); // true

// 12. yield* array inside a for loop (re-entry test)
function* yieldArrayInLoop() {
  for (var i = 0; i < 2; i = i + 1) {
    yield* ["a", "b"];
  }
}
var yl = yieldArrayInLoop();
console.log(yl.next().value); // "a"
console.log(yl.next().value); // "b"
console.log(yl.next().value); // "a"
console.log(yl.next().value); // "b"
console.log(yl.next().done); // true

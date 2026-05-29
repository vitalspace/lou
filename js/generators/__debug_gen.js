function* simple() {
  yield 42;
}

var g = simple();
var s = g.next();
console.log(s.value);
console.log(s.done);

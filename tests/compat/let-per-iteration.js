// let-per-iteration: closures capture per-iteration bindings
var fns = [];
for (let i = 0; i < 3; i++) {
    fns.push(() => i);
}
console.log(fns[0](), fns[1](), fns[2]());

// Verify var does NOT get per-iteration bindings
var fns2 = [];
for (var j = 0; j < 3; j++) {
    fns2.push(() => j);
}
console.log(fns2[0](), fns2[1](), fns2[2]());

// const in for loop (should fail at runtime - assignment to const)
// Skip for now.

// Multiple let declarations
var fns3 = [];
for (let a = 0, b = 10; a < 3; a++, b--) {
    fns3.push(() => a + b);
}
console.log(fns3[0](), fns3[1](), fns3[2]());

// Nested closures
var fns4 = [];
for (let x = 0; x < 3; x++) {
    fns4.push(function outer() {
        return function inner() { return x; };
    });
}
console.log(fns4[0]()(), fns4[1]()(), fns4[2]()());

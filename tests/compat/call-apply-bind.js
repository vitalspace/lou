// Function.prototype.call / apply / bind
// Spec: specs/todos/pendientes/call-apply-bind.md

function greet(greeting) {
    return greeting + " " + this.name;
}
var obj = { name: "Alice" };
console.log(greet.call(obj, "Hello"));
console.log(greet.apply(obj, ["Hi"]));

var bound = greet.bind(obj, "Hey");
console.log(bound());

function introduce() {
    return "I'm " + this.name;
}
var alice = { name: "Alice" };
var bob = { name: "Bob" };
console.log(introduce.call(alice));
console.log(introduce.call(bob));

var boundIntro = introduce.bind(bob);
console.log(boundIntro());

function multiply(a, b) { return a * b; }
var double = multiply.bind(null, 2);
console.log(double(5));
console.log(double(3));

function add(a, b, c) { return a + b + c; }
var addOne = add.bind(null, 1);
console.log(addOne(2, 3));
console.log(addOne(10, 20));

console.log(greet.call({name: "Carol"}, "Hola"));

console.log(greet.apply({name: "Dave"}, ["Bonjour"]));

console.log(greet.apply(null, ["Test"]));

var boundGreet = greet.bind({name: "Eve"});
console.log(boundGreet("Hi"));

function outer() {
    var name = "outer";
    var inner = function() { return this.name; }.bind({name: "bound"});
    return inner();
}
console.log(outer());

var reBound = bound.bind({name: "Frank"});
console.log(reBound("Greetings"));

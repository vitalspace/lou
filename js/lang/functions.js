// Function declaration (function)
function add(a, b) {
    return a + b;
}
console.log(add(3, 4));
console.log(add(10, 20));

// Function declaration (function keyword)
function multiply(a, b, c) {
    return a * b * c;
}
console.log(multiply(2, 3, 4));

// No return
function noop() {
    var x = 1;
    x = x + 1;
}
console.log(noop());

// Function calling function
function square(x) {
    return x * x;
}
function sum_of_squares(a, b) {
    return square(a) + square(b);
}
console.log(sum_of_squares(3, 4));

// If/return
function max(a, b) {
    if (a > b) {
        return a;
    }
    return b;
}
console.log(max(10, 5));
console.log(max(3, 8));

// Arrow function (const)
const double = (x) => x * 2;
console.log(double(5));
console.log(double(0));

// Arrow function (var)
var add2 = (a, b) => a + b;
console.log(add2(10, 20));
console.log(add2(-5, 5));

// Arrow with block body
const max2 = (a, b) => {
    if (a > b) {
        return a;
    }
    return b;
};
console.log(max2(100, 50));
console.log(max2(3, 7));

// Arrow single param no parens not supported (needs parens)
const greet = (name) => "hello " + name;
console.log(greet("world"));

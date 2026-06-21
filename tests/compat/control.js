let total = 0;
for (let i = 1; i <= 5; i = i + 1) {
    total = total + i;
}
console.log(total);

let n = 5;
let fact = 1;
while (n > 1) {
    fact = fact * n;
    n = n - 1;
}
console.log(fact);

const x = 10;
if (x > 5) {
    console.log("big");
} else {
    console.log("small");
}

function greet(name) {
    return "Hello, " + name;
}
console.log(greet("World"));

function fib(n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}
console.log(fib(10));

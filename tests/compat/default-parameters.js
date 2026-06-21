// Basico
function sum(a = 0, b = 0) {
    return a + b;
}
console.log(sum());
console.log(sum(5));
console.log(sum(5, 3));

// Con undefined (debe usar default)
function log(msg = "no message") {
    console.log(msg);
}
log(undefined);
log(null);

// Defaults con expresiones
function makeArray(size = 2, fill = size * 2) {
    const arr = [];
    for (let i = 0; i < size; i++) arr.push(fill);
    return arr;
}
console.log(makeArray());
console.log(makeArray(3, 0));

// Arrow functions
const multiply = (a = 1, b = 1) => a * b;
console.log(multiply());
console.log(multiply(5));

// Defaults acceden a parametros anteriores
function build(first, second = first * 2, third = second * 2) {
    return [first, second, third];
}
console.log(build(1));

// Mixto: con y sin default
function connect(host, port = 8080, secure = false) {
    return (secure ? "https" : "http") + "://" + host + ":" + port;
}
console.log(connect("example.com"));
console.log(connect("example.com", 443));
console.log(connect("example.com", 443, true));

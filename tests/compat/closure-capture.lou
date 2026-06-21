// Closure: captura de let/const del scope exterior
// Spec: specs/todos/pendientes/closure-over-let.md

// Caso simple: captura de variable global declarada con let
let x = 10;
function read() { return x; }
console.log(read());

// Captura con reasignación: closure mantiene el estado entre llamadas
function makeCounter() {
    let count = 0;
    return function() {
        count = count + 1;
        return count;
    };
}
const c = makeCounter();
console.log(c());
console.log(c());
console.log(c());

// Captura múltiple: inner function ve ambos `a` y el argumento `b`
function makePair(a) {
    return function(b) { return a + b; };
}
console.log(makePair(10)(5));

// Arrow function captura let del scope exterior
let msg = "hello";
const greet = () => msg;
console.log(greet());

// Captura + lectura de la variable reasignada fuera del closure
let total = 100;
function getTotal() { return total; }
total = 200;
console.log(getTotal());

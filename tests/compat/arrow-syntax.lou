// Una expresión
const sq = x => x * x;
console.log(sq(5));

// Sin parámetros
const pi = () => 3.14;
console.log(pi());

// Múltiples parámetros
const add = (a, b) => a + b;
console.log(add(2, 3));

// Cuerpo en bloque
const fact = n => {
    if (n < 2) return 1;
    return n * fact(n - 1);
};
console.log(fact(5));

// Como callback
console.log([1, 2, 3].map(x => x * 2));
console.log([1, 2, 3].filter(x => x > 1));

// Rest parameters
const head = (...xs) => xs[0];
console.log(head(1, 2, 3));

// Rest vacío
const empty = (...xs) => xs.length;
console.log(empty());

// Rest solo, identidad
const identity = (...args) => args;
console.log(identity(10, 20, 30));

// Leading params + rest
const f = (a, b, ...rest) => rest;
console.log(f(1, 2, 3, 4, 5));

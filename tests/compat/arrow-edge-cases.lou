// Bug 1: ternario con arrow en ramas
const x = 5;
const sign = x > 0
    ? n => "positive"
    : n => "negative";
console.log(sign(10));
console.log(sign(-10));

// Ternario anidado con arrows
const classify = n =>
    n === 0   ? z => "zero"
    : n > 0   ? p => "positive"
    :          m => "negative";
console.log(classify(5)(1));
console.log(classify(-5)(-1));
console.log(classify(0)(0));

// Arrow en array literal con block bodies
const handlers = [
    x => { return x + 1; },
    x => { return x * 2; }
];
console.log(handlers[0](5));
console.log(handlers[1](5));

// Arrow en array literal con expression bodies
const incs = [(x) => x + 1, (x) => x + 2];
console.log(incs[0](10));
console.log(incs[1](10));
console.log(incs.length);

// Arrow en for init/condition/update
for (let i = 0, pred = (n) => n < 10; pred(i); i++) {
    console.log("for-iter", i);
}

// Arrow en return
function getAdder() {
    return x => x + 1;
}
const add1 = getAdder();
console.log(add1(41));

// Ternario dentro de un arrow body
const classify2 = n => n > 0 ? "pos" : "neg";
console.log(classify2(5));
console.log(classify2(-5));

// Arrow con body complejo (binary, call, member)
const getProp = obj => obj.value;
console.log(getProp({ value: 42 }));

// Empty arrow en array
const noArgs = [() => 1, () => 2, () => 3];
console.log(noArgs[0]());
console.log(noArgs[1]());
console.log(noArgs[2]());
console.log(noArgs.length);

// Arrow en argumentos de llamada
console.log([1, 2, 3].map(n => n * n));
console.log([1, 2, 3, 4, 5].filter(n => n % 2 === 0));
console.log([1, 2, 3, 4, 5].reduce((acc, n) => acc + n, 0));

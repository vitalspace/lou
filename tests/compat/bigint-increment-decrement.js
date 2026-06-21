// BigInt increment / decrement (`++` / `--`)
// `++` y `--` sobre una variable BigInt deben preservar el tipo BigInt
// y hacer aritmética entera BigInt, no coercionar a Number.
//
// Spec: specs/todos/hechos/bigint-increment-decrement.md

// --- Postfix: a++ retorna el valor viejo, side-effect es a+1n ---
let a = 10n;
const a_old = a++;
console.log(a_old);          // 10n
console.log(a);              // 11n
console.log(typeof a);       // bigint

// --- Prefix: ++a retorna el valor nuevo ---
let b = 5n;
const b_new = ++b;
console.log(b_new);          // 6n
console.log(b);              // 6n

// --- Decrement postfix / prefix ---
let c = 7n;
c--;
console.log(c);              // 6n
let d = 3n;
console.log(--d);            // 2n (prefix)
console.log(d);              // 2n

// --- Negativos ---
let neg = 0n;
neg--;
console.log(neg);            // -1n
console.log(typeof neg);     // bigint

let neg2 = -5n;
neg2--;
console.log(neg2);           // -6n

// --- Zero round-trip ---
let z = 0n;
z++;
console.log(z);              // 1n
z--;
console.log(z);              // 0n

// --- BigInt > i64 (no overflow a float) ---
const huge = 2n ** 64n;
let h = huge;
h++;
console.log(h == huge + 1n); // true

// --- Cadena de incrementos ---
let chain = 1n;
chain++;
chain++;
chain++;
console.log(chain);          // 4n

// --- Expresiones compuestas ---
let x = 10n;
console.log(x++ + 1n);       // 11n (postfix: old 10n + 1n)
console.log(x);              // 11n
console.log(++x + 1n);       // 13n (prefix: new 12n + 1n)

// --- En bucle ---
let acc = 0n;
for (let i = 0n; i < 5n; i++) {
    acc++;
}
console.log(acc);            // 5n

// --- Decrement en bucle ---
let down = 10n;
for (let i = 0n; i < 3n; i++) {
    down--;
}
console.log(down);           // 7n

// --- Sanity: Number sigue funcionando ---
let n = 5;
n++;
console.log(n);              // 6
console.log(typeof n);       // number

let m = 5;
m--;
console.log(m);              // 4

// --- Mix Number / BigInt en el mismo scope (sin coerción) ---
let bn = 10n;
let nn = 10;
bn++;
nn++;
console.log(bn);             // 11n
console.log(nn);             // 11
console.log(typeof bn);      // bigint
console.log(typeof nn);      // number
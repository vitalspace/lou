// numeric keys en object literal
console.log({ 0: "a", 1: "b" });

// acceso por índice numérico
const obj = { 0: "x", 1: "y" };
console.log(obj[0]);

// Array.from con array-like
const arrayLike = { 0: "a", 1: "b", length: 2 };
console.log(Array.from(arrayLike));
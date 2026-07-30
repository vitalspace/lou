// --- Iterator Protocol ---

// Array for...of (already works, verify no regression)
const arr = [1, 2, 3];
let sum = 0;
for (const x of arr) {
    sum += x;
}
console.log("array sum:", sum);

// String for...of
const str = "ab";
let strOut = "";
for (const ch of str) {
    strOut += ch;
}
console.log("string chars:", strOut);

// Custom iterable object
const customIterable = {
    [Symbol.iterator]() {
        let i = 0;
        return {
            next() {
                if (i < 3) {
                    return { value: i++, done: false };
                }
                return { done: true };
            }
        };
    }
};
let customSum = 0;
for (const x of customIterable) {
    customSum += x;
}
console.log("custom iterable sum:", customSum);

// Generator function
function* gen() {
    yield 10;
    yield 20;
    yield 30;
}
let genSum = 0;
for (const x of gen()) {
    genSum += x;
}
console.log("generator sum:", genSum);

// Nested iteration
const nested = {
    [Symbol.iterator]() {
        let i = 0;
        return {
            next() {
                if (i < 2) {
                    return { value: i++ * 10, done: false };
                }
                return { done: true };
            }
        };
    }
};
let nestedSum = 0;
for (const x of nested) {
    nestedSum += x;
}
console.log("nested sum:", nestedSum);

// Symbol.iterator is a function
console.log("typeof Symbol.iterator:", typeof Symbol.iterator);

// Array iterator via Symbol.iterator
const arrIter = arr[Symbol.iterator]();
console.log("arrIter next:", arrIter.next().value);
console.log("arrIter next:", arrIter.next().value);
console.log("arrIter next:", arrIter.next().value);
console.log("arrIter done:", arrIter.next().done);

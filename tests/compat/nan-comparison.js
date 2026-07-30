// NaN comparisons — ES spec: any relational comparison with NaN returns false
console.log(NaN <= 5);       // false
console.log(NaN >= 5);       // false
console.log(NaN < 5);        // false
console.log(NaN > 5);        // false
console.log(5 <= NaN);       // false
console.log(5 >= NaN);       // false
console.log(5 < NaN);        // false
console.log(5 > NaN);        // false
console.log(NaN <= NaN);     // false
console.log(NaN >= NaN);     // false
console.log(NaN < NaN);      // false
console.log(NaN > NaN);      // false
console.log(NaN <= Infinity);// false
console.log(NaN >= -Infinity);// false

// Non-NaN comparisons still work
console.log(3 <= 5);         // true
console.log(5 >= 3);         // true
console.log(3.5 <= 3.5);     // true

// UpdateExpression (++/--) on MemberAccess and ArrayIndex
// Reference output: Node.js

// --- Basic MemberAccess post-increment ---
let o = {x: 5, y: 10};
let r1 = o.x++;
console.log(r1);          // 5 (old value)
console.log(o.x);         // 6

// --- Basic MemberAccess pre-increment ---
let r2 = ++o.y;
console.log(r2);          // 11 (new value)
console.log(o.y);         // 11

// --- Basic ArrayIndex post-increment ---
let a = [1, 2, 3];
let r3 = a[0]++;
console.log(r3);          // 1 (old value)
console.log(a);           // [2, 2, 3]

// --- Basic ArrayIndex pre-increment ---
let r4 = ++a[1];
console.log(r4);          // 3 (new value)
console.log(a);           // [2, 3, 3]

// --- Post-decrement MemberAccess ---
let stats = {hits: 10};
let r5 = stats.hits--;
console.log(r5);          // 10
console.log(stats.hits);  // 9

// --- Pre-decrement ArrayIndex ---
let b = [5, 10, 15];
let r6 = --b[2];
console.log(r6);          // 14
console.log(b);           // [5, 10, 14]

// --- Chained MemberAccess ---
let deep = {a: {b: 1}};
deep.a.b++;
console.log(deep.a.b);    // 2

// --- Mixed with other operators ---
let arr = [100];
let r7 = arr[0]++ + 50;
console.log(r7);          // 150 (100 + 50)
console.log(arr);         // [101]

// --- Plain Identifier still works ---
let x = 5;
let r8 = x++;
console.log(r8);          // 5
console.log(x);           // 6

let r9 = ++x;
console.log(r9);          // 7
console.log(x);           // 7

// --- Expression index ---
let c = [10, 20, 30];
let idx = 1;
c[idx]--;
console.log(c);           // [10, 19, 30]

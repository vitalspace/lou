// UpdateExpression on LeftHandSideExpression
// Pre/post increment and decrement on identifiers, member access, and array index.

// Pre-increment on identifier
let i = 5;
console.log(++i);  // 6
console.log(i);    // 6

// Post-increment on identifier
let j = 5;
console.log(j++);  // 5
console.log(j);    // 6

// Pre-increment on member access
let o = {x: 10};
console.log(++o.x);  // 11
console.log(o.x);    // 11

// Post-increment on member access
let o2 = {x: 10};
console.log(o2.x++); // 10
console.log(o2.x);   // 11

// Pre-increment on array index
let a = [1, 2, 3];
console.log(++a[0]);  // 2
console.log(a[0]);    // 2

// Post-increment on array index
let a2 = [1, 2, 3];
console.log(a2[0]++); // 1
console.log(a2[0]);   // 2

// Pre-decrement
let k = 10;
console.log(--k);  // 9
console.log(k);    // 9

// Post-decrement
let l = 10;
console.log(l--);  // 10
console.log(l);    // 9

// Pre-decrement on member
let o3 = {y: 7};
console.log(--o3.y);  // 6
console.log(o3.y);    // 6

// Pre-decrement on array index
let a3 = [5, 6];
console.log(--a3[1]);  // 5
console.log(a3[1]);    // 5

// Post-decrement on member
let o4 = {z: 7};
console.log(o4.z--);  // 7
console.log(o4.z);    // 6

// Counter pattern with member
const counter = { count: 0 };
counter.count++;
counter.count++;
counter.count++;
console.log(counter.count);  // 3

// Counter pattern with array
const arr = [10, 20, 30];
arr[0]++;
arr[1]++;
console.log(arr);  // [ 11, 21, 30 ]

// Pre-increment in expression
let n = 5;
const m = ++n * 2;
console.log(m);  // 12
console.log(n);  // 6

// Post-increment in expression
let p = 5;
const q = p++ * 2;
console.log(q);  // 10
console.log(p);  // 6

// For loop counter (uses ++ in increment position)
let sum = 0;
for (let x = 0; x < 5; x++) {
    sum = sum + x;
}
console.log(sum);  // 10

// Increment on chained member
const nested = { inner: { val: 100 } };
nested.inner.val++;
console.log(nested.inner.val);  // 101

// Pre-increment chained
const obj = { a: { b: 50 } };
console.log(++obj.a.b);  // 51
console.log(obj.a.b);    // 51

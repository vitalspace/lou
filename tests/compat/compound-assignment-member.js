// Compound assignment to member expressions (`obj.x += 5`).
// ECMAScript allows `+=`, `-=`, `*=`, `/=`, `%=` on any LeftHandSideExpression,
// including member access (`obj.prop`, `obj["key"]`) and array index (`arr[i]`).

// --- Basic numeric compound on MemberAccess ---

var obj = { x: 10 };
obj.x += 5;
console.log(obj.x);  // 15
obj.x -= 3;
console.log(obj.x);  // 12
obj.x *= 2;
console.log(obj.x);  // 24
obj.x /= 4;
console.log(obj.x);  // 6
obj.x %= 4;
console.log(obj.x);  // 2

// --- String concatenation via += on MemberAccess ---

var s = { name: "hello" };
s.name += " world";
console.log(s.name);  // "hello world"

// --- Computed member access via string key ---

var data = { count: 100, label: "" };
data["count"] += 23;
console.log(data["count"]);  // 123
data["label"] += "abc";
console.log(data["label"]);  // "abc"

// --- Array index compound assignment ---

var arr = [10, 20, 30];
arr[0] += 5;
console.log(arr[0]);  // 15
arr[1] -= 10;
console.log(arr[1]);  // 10
arr[2] *= 2;
console.log(arr[2]);  // 60

// --- String-keyed array index ---

var obj2 = {};
obj2["k"] = 7;
obj2["k"] += 3;
console.log(obj2["k"]);  // 10

// --- Nested member access ---

var deep = { a: { b: 1, c: 2 } };
deep.a.b += 10;
console.log(deep.a.b);  // 11
deep.a.c -= 5;
console.log(deep.a.c);  // -3

// --- Multiple compound assignments in sequence ---

var counter = { count: 0, total: 0 };
counter.count += 1;
counter.count += 1;
counter.count += 1;
console.log(counter.count);  // 3
counter.total += counter.count;
console.log(counter.total);  // 3

// --- Compound assignment on local variable still works (regression) ---

var localVar = 50;
localVar += 25;
console.log(localVar);  // 75

// --- Compound assignment expression value (return value) ---

var r = (obj.x += 100);
console.log(r);     // 102
console.log(obj.x); // 102

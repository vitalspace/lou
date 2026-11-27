// Multiple declarators in one const/let/var statement
const a = 10, b = 2;
console.log(a, b, a / b);

let x = 3, y = 4;
console.log(x, y, x * y);

var p = 1, q = 2;
console.log(p, q, p + q);

// Later declarators may use earlier ones
const s = 5, t = s + 1, u = s * t;
console.log(s, t, u);

// Inside a function
function scope() {
    const m = 2, n = 3;
    return m + n;
}
console.log(scope());

// In a nested block
{
    let i = 7, j = 8;
    console.log(i + j);
}

// Multi-declarator in a for-loop initializer
for (let i = 0, j = 10; i < 2; i++, j--) {
    console.log(i, j);
}

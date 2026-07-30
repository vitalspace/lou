// for-var-no-init.js — canonical Node reference
// Exercises ECMAScript §14.7.4.5 ForBinding without an initializer
// (`var`/`let` allowed, `const` is a SyntaxError).

// 1) `for (var i; i < 3; i++)` — uninitialized var, then while-condition
for (var i; i < 3; i++) {
    console.log("var-no-init:", i);
}

// 2) `for (let x;;) { break; }` — uninitialized let with no condition
for (let x;;) {
    console.log("let-no-init:", x);
    break;
}

// 3) Multiple bindings, some with init, some without
for (var a = 0, b; a < 2; a++) {
    console.log("mixed:", a, b);
}

// 4) Uninitialized var followed by assignment via postfix `++`
for (var k; k < 4;) {
    console.log("post-inc:", k);
    k++;
}

// 5) Const without init MUST be a SyntaxError
let const_threw = false;
try {
    eval("for (const c;;) {}");
} catch (e) {
    const_threw = (e instanceof SyntaxError);
}
console.log("const-no-init:", const_threw);

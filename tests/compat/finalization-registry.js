// FinalizationRegistry — JS reference (Node.js)
// Tests constructor, register, unregister API surface

// --- Basic construction ---
const registry = new FinalizationRegistry((held) => {
    console.log("Collected:", held);
});
console.log("constructor: ok");

// --- typeof ---
console.log("typeof:", typeof registry);

// --- register with object target ---
let obj1 = {};
registry.register(obj1, "value-1");
console.log("register: ok");

// --- register with unregisterToken ---
let obj2 = {};
registry.register(obj2, "value-2", obj2);
console.log("register with token: ok");

// --- unregister (Token not found) ---
console.log("unregister missing:", registry.unregister({}));

// --- unregister (Token found) ---
console.log("unregister found:", registry.unregister(obj2));

// --- unregister again (should be false) ---
console.log("unregister again:", registry.unregister(obj2));

// --- register with no unregisterToken ---
let obj3 = {};
registry.register(obj3, "no-token-value");
console.log("register no token: ok");

// --- TypeError: target must be an object ---
try {
    registry.register(42, "bad");
    console.log("register primitive: no error");
} catch (e) {
    console.log("register primitive:", e instanceof TypeError);
}

// --- register with string target should throw ---
try {
    registry.register("hello", "bad");
    console.log("register string: no error");
} catch (e) {
    console.log("register string:", e instanceof TypeError);
}

// --- register with null target should throw ---
try {
    registry.register(null, "bad");
    console.log("register null: no error");
} catch (e) {
    console.log("register null:", e instanceof TypeError);
}

// --- instanceof ---
console.log("instanceof FinalizationRegistry:", registry instanceof FinalizationRegistry);
console.log("instanceof Object:", registry instanceof Object);
console.log("not instanceof Array:", registry instanceof Array);

console.log("done");

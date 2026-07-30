// Test globalThis (ES2020)
console.log("typeof:", typeof globalThis);
console.log("self_ref:", globalThis === globalThis.globalThis);
console.log("is_object:", typeof globalThis === "object");

// Property write/read through globalThis
globalThis.testVar = 42;
console.log("testVar:", testVar);
console.log("prop_read:", globalThis.testVar);

// Verify both paths return same value
console.log("both_same:", testVar === globalThis.testVar);

// String.prototype.padEnd / padStart — compat reference (Node.js).
//
// Scope covers both ASCII and Unicode (codepoint-aware length) plus NaN /
// ±Infinity / huge finite target lengths. Matches V8's behavior of refusing
// to allocate an astronomical buffer when targetLength is effectively infinite.

// ===== no-arg sanity =====
console.log("abc".padEnd());
console.log("abc".padStart());

// ===== ASCII baselines =====
console.log("abc".padEnd(6));
console.log("abc".padEnd(6, "."));
console.log("abc".padEnd(3));
console.log("abc".padEnd(1));
console.log("abc".padEnd(6, ""));
console.log("abc".padStart(6));
console.log("abc".padStart(6, "."));
console.log("5".padStart(3, "0"));
console.log("abc".padStart(3));
console.log("abc".padStart(1));
console.log("x".padEnd(4, "abc"));
console.log("x".padStart(4, "abc"));
console.log("hi".padEnd(8, "xy"));
console.log("hi".padStart(8, "xy"));

// ===== boolean / float coercion =====
console.log("abc".padEnd(true));
console.log("abc".padEnd(false));
console.log("abc".padStart(true));
console.log("abc".padStart(false));
console.log("abc".padEnd(5.7));
console.log("abc".padStart(5.7));
console.log("abc".padEnd(2.4));
console.log("abc".padStart(2.4));
console.log("abc".padEnd(-1.5));
console.log("abc".padStart(-1.5));
console.log("x".padEnd(3.9, "."));
console.log("x".padStart(3.9, "."));
console.log("hi".padEnd(10, ""));
console.log("hi".padStart(10, ""));

// ===== Unicode (codepoint-counted) =====
console.log("Ü".padEnd(2));
console.log("Ü".padStart(2));
console.log("Ü".padEnd(3, "."));
console.log("Ü".padStart(3, "."));
console.log("café".padEnd(6, "."));
console.log("café".padStart(6, "."));
console.log("ñoño".padEnd(5));
console.log("ñoño".padStart(5));

// Multi-byte padString truncates at codepoint boundary
console.log("Ü".padEnd(2, "ab"));
console.log("Ü".padStart(2, "ab"));
console.log("Ü".padEnd(4, "éé"));
console.log("Ü".padStart(4, "éé"));

// ===== NaN / -Infinity targetLength =====
// Node returns the original string for these; +Infinity and other pathologically
// large values throw `RangeError: Invalid string length` in V8, so they're
// covered by unit tests only — see src/builtins/string/{padEnd,padStart}.zig.
console.log("abc".padEnd(NaN));
console.log("abc".padStart(NaN));
console.log("abc".padEnd(-Infinity));
console.log("abc".padStart(-Infinity));

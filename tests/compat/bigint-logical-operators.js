// BigInt logical operators (&&, ||, ??)
// Los operadores &&, || y ?? deben retornar uno de los operandos (cortocircuito),
// no un booleano. Esto aplica a todos los tipos, no solo BigInt.
//
// Node.js reference — debe producir salida identica a bigint-logical-operators.lou
//
// Spec: specs/todos/pendientes/bigint-logical-operators.md

// --- BigInt && : retorna a si falsy, sino b ---
console.log("--- BigInt && ---");
console.log(0n && 1n);      // 0n
console.log(1n && 2n);      // 2n
console.log(0n && 2n);      // 0n
console.log(1n && 0n);      // 0n

// --- BigInt || : retorna a si truthy, sino b ---
console.log("--- BigInt || ---");
console.log(0n || 1n);      // 1n
console.log(1n || 2n);      // 1n
console.log(0n || 0n);      // 0n
console.log(1n || 0n);      // 1n

// --- BigInt ?? : retorna a si no null/undefined, sino b ---
console.log("--- BigInt ?? ---");
console.log(null ?? 42n);        // 42n
console.log(undefined ?? 42n);  // 42n
console.log(0n ?? 42n);         // 0n (0n no es nullish)
console.log(1n ?? 42n);         // 1n

// --- Number && || ?? : también retorna operando, no booleano ---
console.log("--- Number && || ?? ---");
console.log(0 && "x");      // 0
console.log(1 && "x");      // "x"
console.log(0 || "x");      // "x"
console.log(1 || "x");      // 1
console.log(null ?? "x");   // "x"
console.log(undefined ?? "x"); // "x"
console.log(0 ?? "x");      // 0
console.log("" ?? "x");     // ""

// --- Boolean && || : operando es booleano, retorna operando ---
console.log("--- Boolean && || ---");
console.log(true && false); // false
console.log(false && true); // false
console.log(true || false); // true
console.log(false || true); // true

// --- String && || : operando es string ---
console.log("--- String && || ---");
console.log("" && "x");     // ""
console.log("a" && "x");    // "x"
console.log("" || "x");     // "x"
console.log("a" || "x");    // "a"

// --- Cortocircuito: && no evalúa b si a es falsy ---
console.log("--- Cortocircuito && ---");
let counter = 0;
0n && ++counter;
console.log(counter);       // 0 (no se ejecutó)

counter = 0;
1n && ++counter;
console.log(counter);       // 1

// --- Cortocircuito: || no evalúa b si a es truthy ---
console.log("--- Cortocircuito || ---");
counter = 0;
1n || ++counter;
console.log(counter);       // 0 (no se ejecutó)

counter = 0;
0n || ++counter;
console.log(counter);       // 1

// --- Encadenamiento mixto BigInt / Number ---
console.log("--- Mixto ---");
console.log(1n && 1);       // 1 (number)
console.log(1n || 0);       // 1n
console.log(0n || 1);       // 1 (number)
console.log(1 && 1n);       // 1n

// --- typeof para verificar que retorna BigInt, no boolean ---
console.log("--- typeof ---");
const r1 = 0n && 1n;
console.log(typeof r1);     // bigint
const r2 = 1n || 2n;
console.log(typeof r2);     // bigint
const r3 = 0 && "x";
console.log(typeof r3);     // number

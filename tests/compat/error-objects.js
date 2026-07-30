// Error Objects conformance test
// Spec: specs/todos/pendientes/error-objects.md
// Reference: Node.js ES2025

console.log("--- Error base ---");
const e1 = new Error("base error");
console.log("name:", e1.name);
console.log("message:", e1.message);
console.log("toString:", e1.toString());
console.log("instanceof Error:", e1 instanceof Error);

console.log("--- TypeError ---");
const e2 = new TypeError("not a function");
console.log("name:", e2.name);
console.log("message:", e2.message);
console.log("toString:", e2.toString());
console.log("instanceof TypeError:", e2 instanceof TypeError);
console.log("instanceof Error:", e2 instanceof Error);

console.log("--- RangeError ---");
const e3 = new RangeError("out of range");
console.log("name:", e3.name);
console.log("message:", e3.message);
console.log("toString:", e3.toString());
console.log("instanceof RangeError:", e3 instanceof RangeError);
console.log("instanceof Error:", e3 instanceof Error);

console.log("--- ReferenceError ---");
const e4 = new ReferenceError("x is not defined");
console.log("name:", e4.name);
console.log("message:", e4.message);
console.log("toString:", e4.toString());
console.log("instanceof ReferenceError:", e4 instanceof ReferenceError);
console.log("instanceof Error:", e4 instanceof Error);

console.log("--- SyntaxError ---");
const e5 = new SyntaxError("unexpected token");
console.log("name:", e5.name);
console.log("message:", e5.message);
console.log("toString:", e5.toString());
console.log("instanceof SyntaxError:", e5 instanceof SyntaxError);
console.log("instanceof Error:", e5 instanceof Error);

console.log("--- EvalError ---");
const e6 = new EvalError("eval disabled");
console.log("name:", e6.name);
console.log("instanceof EvalError:", e6 instanceof EvalError);
console.log("instanceof Error:", e6 instanceof Error);

console.log("--- URIError ---");
const e7 = new URIError("malformed URI");
console.log("name:", e7.name);
console.log("instanceof URIError:", e7 instanceof URIError);
console.log("instanceof Error:", e7 instanceof Error);

console.log("--- throw + catch: Error ---");
try {
    throw new Error("oops");
} catch (e) {
    console.log("caught:", e.toString());
    console.log("instanceof Error:", e instanceof Error);
}

console.log("--- throw + catch: TypeError ---");
try {
    throw new TypeError("bad type");
} catch (e) {
    console.log("caught:", e.name, e.message);
    console.log("instanceof TypeError:", e instanceof TypeError);
    console.log("instanceof Error:", e instanceof Error);
}

console.log("--- throw + catch: RangeError ---");
try {
    throw new RangeError("index 99 out of bounds");
} catch (e) {
    console.log("caught:", e.name, e.message);
    console.log("instanceof RangeError:", e instanceof RangeError);
}

console.log("--- no message ---");
const empty = new Error();
console.log("name:", empty.name);
console.log("message:", empty.message);
console.log("toString:", empty.toString());

console.log("--- non-string message ---");
const num_msg = new Error(42);
console.log("name:", num_msg.name);
console.log("message:", num_msg.message);
console.log("toString:", num_msg.toString());

console.log("--- instanceof non-matching ---");
console.log("plain Error instanceof TypeError:", (new Error()) instanceof TypeError);
console.log("plain Error instanceof RangeError:", (new Error()) instanceof RangeError);

console.log("--- rethrow ---");
try {
    try {
        throw new URIError("bad uri");
    } catch (inner) {
        if (inner instanceof URIError) {
            throw inner;
        }
    }
} catch (re) {
    console.log("recaught:", re.name, re.message);
}

console.log("--- constructor without new ---");
try {
    Error("plain call");
    console.log("Error() returned undefined");
} catch (err) {
    console.log("Error() threw:", err.name);
}

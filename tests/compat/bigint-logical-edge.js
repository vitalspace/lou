// BigInt logical operators - complex short-circuit tests
// Node.js reference

let sideEffect = false;
const result = true || (sideEffect = true);
console.log("sideEffect should be false:", sideEffect);
console.log("result:", result);

sideEffect = false;
const result2 = false || (sideEffect = true) || "default";
console.log("sideEffect should be true:", sideEffect);
console.log("result2:", result2);

sideEffect = false;
const result3 = true && (sideEffect = true);
console.log("sideEffect should be true:", sideEffect);
console.log("result3:", result3);

sideEffect = false;
const result4 = false && (sideEffect = true);
console.log("sideEffect should be false:", sideEffect);
console.log("result4:", result4);

sideEffect = false;
const result5 = (sideEffect = true) ?? "default";
console.log("sideEffect should be true:", sideEffect);
console.log("result5:", result5);

sideEffect = false;
const result6 = null ?? (sideEffect = true);
console.log("sideEffect should be true:", sideEffect);
console.log("result6:", result6);

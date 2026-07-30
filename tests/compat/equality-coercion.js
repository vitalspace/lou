// ECMAScript 7.2.14 Abstract Equality Comparison reference (Node.js).
// Prints "true" or "false" for each scenario in spec order.

// === Type coercion chains ===
console.log("0==''", 0 == "");
console.log("0=='0'", 0 == "0");
console.log("''=='0'", "" == "0");
console.log("false=='0'", false == "0");
console.log("false==0", false == 0);
console.log("false==''", false == "");
console.log("true=='1'", true == "1");
console.log("true==1", true == 1);

// === null / undefined ===
console.log("null==undef", null == undefined);
console.log("null==null", null == null);
console.log("null==0", null == 0);
console.log("null==''", null == "");
console.log("undef==0", undefined == 0);
console.log("undef==''", undefined == "");

// === Object ↔ primitive (ToPrimitive with default hint) ===
console.log("[1]==1", [1] == 1);
console.log("[]==0", [] == 0);
console.log("[]==''", [] == "");
console.log("[1]=='1'", [1] == "1");
console.log("[1,2]=='1,2'", [1, 2] == "1,2");
console.log("[] == false", [] == false);
console.log("[] == ![]", [] == ![]);

// === Number ↔ Number (cross-tag numeric compare) ===
console.log("1==1.0", 1 == 1.0);
console.log("0==-0", 0 == -0);

// === Strict inequality counterpart (sanity) ===
console.log("0!==''", 0 !== "");
console.log("false!==0", false !== 0);
console.log("[]!==0", [] !== 0);
console.log("null!==undef", null !== undefined);

// === NaN never equals itself ===
console.log("NaN==NaN", NaN == NaN);
console.log("NaN==0", NaN == 0);

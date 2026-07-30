// ===== parseInt basics =====
console.log(parseInt("42"));             // 42
console.log(parseInt("  42  "));         // 42
console.log(parseInt("42px"));           // 42
console.log(parseInt("+42"));            // 42
console.log(parseInt("-42"));            // -42
console.log(parseInt("abc"));            // NaN
console.log(parseInt(""));               // NaN
console.log(parseInt(" "));              // NaN

// ===== parseInt with explicit radix =====
console.log(parseInt("FF", 16));         // 255
console.log(parseInt("ff", 16));         // 255 (case-insensitive digits)
console.log(parseInt("1010", 2));        // 10
console.log(parseInt("zz", 36));         // 1295
console.log(parseInt("077", 8));         // 63
console.log(parseInt("0xFF", 16));       // 255 (also strips 0x prefix)
console.log(parseInt("10", 37));         // NaN (radix out of range)
console.log(parseInt("10", 1));          // NaN (radix out of range)

// ===== parseInt auto-detect radix =====
console.log(parseInt("42", undefined));  // 42
console.log(parseInt("42", 0));          // 42 (auto: decimal)
console.log(parseInt("0xFF"));           // 255 (auto: hex)
console.log(parseInt("0X10"));           // 16 (auto: hex)
console.log(parseInt("0o77"));           // 0 (no auto: 0o not detected by parseInt)
console.log(parseInt("0b1010"));         // 0 (no auto: 0b not detected by parseInt)
console.log(parseInt("077"));            // 77 (no legacy octal)

// ===== parseInt parseFailure inside valid input =====
console.log(parseInt("0xZZZ"));          // NaN (Z exceeds base 16)
console.log(parseInt("0xFF", 10));       // 0 (x is not valid in base 10)

// ===== parseFloat basics =====
console.log(parseFloat("3.14"));         // 3.14
console.log(parseFloat("  3.14  "));     // 3.14
console.log(parseFloat("3.14abc"));      // 3.14
console.log(parseFloat("-3.14"));        // -3.14
console.log(parseFloat("+3.14"));        // 3.14
console.log(parseFloat(".5"));           // 0.5
console.log(parseFloat("3.14e2"));       // 314
console.log(parseFloat("abc"));          // NaN
console.log(parseFloat(""));             // NaN
console.log(parseFloat(" "));            // NaN

// ===== parseFloat case-INsensitive Infinity = V8 returns NaN only for exact "Infinity"
console.log(parseFloat("infinity"));     // NaN (V8 is case-sensitive)
console.log(parseFloat("INFINITY"));     // NaN (V8 is case-sensitive)
console.log(parseFloat("Inf"));          // NaN (only full literal)

// ===== Non-string input coercion =====
console.log(parseInt(true));             // NaN ("true" has no digits)
console.log(parseInt(42));               // 42
console.log(parseInt(3.14));             // 3 (parseInt truncates)
console.log(parseFloat(true));           // NaN
console.log(parseFloat(42));             // 42

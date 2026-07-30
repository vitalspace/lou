// Intl minimal compat test (NumberFormat + DateTimeFormat + Collator)
// Note: Lou's Intl implementation supports en-US only; other locales
// fall back to en-US formatting.

// --- NumberFormat ---
const nf = new Intl.NumberFormat("en-US");
console.log(nf.format(1234567.89));

const nfDe = new Intl.NumberFormat("de-DE");
console.log(nfDe.format(1234567.89));

const nfEs = new Intl.NumberFormat("es-MX");
console.log(nfEs.format(1234567.89));

const nfJa = new Intl.NumberFormat("ja-JP");
console.log(nfJa.format(1234567.89));

// --- DateTimeFormat ---
const dtf = new Intl.DateTimeFormat("en-US");
const d = new Date(1705314600000);
console.log(dtf.format(d));

// --- Collator ---
const coll = new Intl.Collator("en-US");
console.log(coll.compare("a", "b"));
console.log(coll.compare("b", "a"));
console.log(coll.compare("a", "a"));

const collBase = new Intl.Collator("en-US", { sensitivity: "base" });
console.log(collBase.compare("A", "a"));
console.log(collBase.compare("Z", "a"));

// NOTE: Lou's builtin objects do not support extracting method references
// as callable functions (coll.compare is undefined). Use a wrapper.
console.log(["banana", "apple", "cherry"].sort((a, b) => coll.compare(a, b)));

// Date object — basic functionality.
// Tests fixed (non-now-relative) dates only; timezones not exercised.

const fromTs = new Date(1705314600000);
console.log(fromTs.toISOString());
console.log(fromTs.getTime());
console.log(fromTs.getUTCFullYear());
console.log(fromTs.getUTCMonth());
console.log(fromTs.getUTCDate());
console.log(fromTs.getUTCHours());
console.log(fromTs.getUTCMinutes());
console.log(fromTs.getUTCDay());

const fromISO = new Date("2024-01-15T10:30:00Z");
console.log(fromISO.toISOString());
console.log(fromISO.getTime());

// toString returns a non-empty string
console.log(typeof fromTs.toString());
console.log(fromTs.toString().length > 0);

// Static methods
console.log(Date.now() > 0);
console.log(Date.parse("2024-01-15T10:30:00Z"));
console.log(Date.UTC(2024, 0, 15, 10, 30, 0));

// Setters
const sd = new Date(1705314600000);
sd.setFullYear(2025);
console.log(sd.getUTCFullYear());

// Subtraction returns a number (ms diff)
const d1 = new Date("2024-01-01T00:00:00Z");
const d2 = new Date("2024-12-31T00:00:00Z");
console.log(d2 - d1);

// Equality of two dates with same timestamp
const a = new Date(1705314600000);
const b = new Date(1705314600000);
console.log(a.getTime() === b.getTime());

// Local getters (timezone-dependent; just check they are numbers)
const d3 = new Date("2024-01-15T10:30:00Z");
console.log(typeof d3.getFullYear() === "number");
console.log(typeof d3.getMonth() === "number");
console.log(typeof d3.getHours() === "number");

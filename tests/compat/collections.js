const arr = [3, 1, 4, 1, 5, 9, 2, 6];
console.log(arr.length);
console.log(arr.push(7));
console.log(arr);
console.log(arr.pop());
console.log(arr);
console.log(arr.indexOf(4));
console.log(arr.includes(5));
console.log(arr.slice(2, 5));
console.log(arr.reverse());
console.log(arr.join(","));
console.log(Array.from("abc"));
console.log(Array.isArray([1, 2, 3]));

const m = new Map();
m.set("a", 1);
m.set("b", 2);
console.log(m.get("a"));
console.log(m.has("b"));
console.log(m.size);

const s = new Set([1, 2, 3, 2, 1]);
console.log(s.size);
console.log(s.has(2));

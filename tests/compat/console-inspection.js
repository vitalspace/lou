console.time("test")
const obj = { a: 1, nested: { b: 2 } };
console.dir(obj, { depth: 0, colors: false });
console.dir(obj, { depth: null, colors: false });
console.table([{ a: 1, b: 2 }, { a: 3, b: 4 }]);
console.table(["x", "y"]);
console.table({ x: { a: 1 }, y: { b: 2 } });
console.table([{ a: 1, b: 2 }, { a: 3 }], ["b"]);
console.timeEnd("test")

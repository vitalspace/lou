// Object.keys
console.log(Object.keys({a:1, b:2}));  // ["a", "b"]

// Object.assign
console.log(Object.assign({}, {a:1}, {b:2}));  // {a:1, b:2}

// Object.create (si es soportado)
const obj = Object.create(null);
console.log(obj);  // {} sin prototipo

// Object.entries
console.log(Object.entries({a:1, b:2}));  // [["a",1],["b",2]]

// Object.values
console.log(Object.values({a:1, b:2}));  // [1,2]

// Object.hasOwn
console.log(Object.hasOwn({a:1}, "a"));  // true
console.log(Object.hasOwn({a:1}, "b"));  // false
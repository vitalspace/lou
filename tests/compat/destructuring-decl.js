// Destructuring in variable declarations

console.log("=== const object destructuring ===")
const { a, b } = { a: 1, b: 2 }
console.log(a + b)

console.log("=== const array destructuring ===")
const [x, y] = [10, 20]
console.log(x + y)

console.log("=== let object destructuring ===")
let { name, age } = { name: "Alice", age: 30 }
console.log(name + ":" + age)

console.log("=== let array destructuring ===")
let [p, q] = [3, 4]
console.log(p + q)

console.log("=== var object destructuring ===")
var { first } = { first: "hello" }
console.log(first)

console.log("=== var array destructuring ===")
var [z] = [99]
console.log(z)

console.log("=== defaults in const ===")
const { m = 10, n = 20 } = { m: 5 }
console.log(m + n)

console.log("=== defaults in array ===")
const [u = 100, v = 200] = [50]
console.log(u + v)

console.log("=== rename in const ===")
const { xx: renamed } = { xx: 42 }
console.log(renamed)

console.log("=== rest in array ===")
const [head, ...tail] = [1, 2, 3, 4]
console.log(head + tail.length)

console.log("=== nested object in const ===")
const { outer: { inner } } = { outer: { inner: 77 } }
console.log(inner)

console.log("=== nested array in const ===")
const [[a1, a2], b1] = [[1, 2], 3]
console.log(a1 + a2 + b1)

console.log("=== mixed in let ===")
let { profile: { id } } = { profile: { id: 900 } }
console.log(id)

console.log("=== elision in const ===")
const [, , third] = [10, 20, 30]
console.log(third)

console.log("=== whole-pattern default in let ===")
let { w = 0 } = {}
console.log(w)

console.log("=== combined ===")
const { person: { details: { score: s } } } = { person: { details: { score: 88 } } }
console.log(s)

// Destructuring in assignment expressions

console.log("=== object destructuring assignment ===")
let a, b
({ a, b } = { a: 1, b: 2 })
console.log(a + b)

console.log("=== array destructuring assignment ===")
let x, y
[x, y] = [10, 20]
console.log(x + y)

console.log("=== rename in object ===")
let renamed
({ oldName: renamed } = { oldName: 42 })
console.log(renamed)

console.log("=== rest in array ===")
let head, tail
[head, ...tail] = [1, 2, 3, 4]
console.log(head + tail.length)

console.log("=== elision in array ===")
let first, third
[first, , third] = [10, 20, 30]
console.log(first + third)

console.log("=== nested object ===")
let inner
({ outer: { inner } } = { outer: { inner: 77 } })
console.log(inner)

console.log("=== nested array in object ===")
let a1, a2
({ arr: [a1, a2] } = { arr: [5, 6] })
console.log(a1 + a2)

console.log("=== nested object in array ===")
let n1
[{ name: n1 }, ] = [{ name: "Alice" }]
console.log(n1)

console.log("=== assignment returns RHS ===")
let r
const result = ({ r } = { r: 99 })
console.log(result.r + r)

console.log("=== array assignment returns RHS ===")
let p, q
const arrResult = [p, q] = [7, 8]
console.log(p + q + arrResult.length)

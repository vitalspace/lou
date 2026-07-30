console.log("=== Nested object destructuring ===")

function f1({ a: { b, c } }) {
  return b + c
}

console.log(f1({ a: { b: 1, c: 2 } }))
console.log(f1({ a: { b: 10, c: 20 } }))

console.log("=== Nested object with rename ===")

function f2({ a: { b: x, c: y } }) {
  return x + y
}

console.log(f2({ a: { b: 3, c: 4 } }))

console.log("=== Deeply nested ===")

function f3({ a: { b: { c } } }) {
  return c
}

console.log(f3({ a: { b: { c: 42 } } }))

console.log("=== Nested with defaults ===")

function f4({ a: { b = 10, c = 20 } }) {
  return b + c
}

console.log(f4({ a: { b: 1 } }))
console.log(f4({ a: {} }))

console.log("=== Nested whole-pattern default ===")

function f5({ a: { b, c } = { b: 5, c: 5 } }) {
  return b + c
}

console.log(f5({ a: { b: 1, c: 2 } }))
console.log(f5({}))

console.log("=== Nested array inside object ===")

function f6({ items: [first, second] }) {
  return first + second
}

console.log(f6({ items: [10, 20] }))

console.log("=== Nested object inside array ===")

function f7([{ x, y }]) {
  return x + y
}

console.log(f7([{ x: 3, y: 4 }]))

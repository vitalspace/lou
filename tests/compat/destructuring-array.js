console.log("=== Basic array destructuring ===")

function f1([a, b]) {
  return a + b
}

console.log(f1([1, 2]))
console.log(f1([10, 20]))
console.log(f1([0, 0]))

console.log("=== Array destructuring with rest ===")

function f2([first, ...rest]) {
  return first + rest.length
}

console.log(f2([1, 2, 3, 4]))
console.log(f2([10]))

console.log("=== Array destructuring with defaults ===")

function f3([a = 10, b = 20]) {
  return a + b
}

console.log(f3([1, 2]))
console.log(f3([5]))
console.log(f3([]))

console.log("=== Array destructuring with elision ===")

function f4([a, , c]) {
  return a + c
}

console.log(f4([1, 2, 3]))
console.log(f4([5, 6, 7]))

console.log("=== Array destructuring whole-pattern default ===")

function f5([x, y] = [0, 0]) {
  return x + y
}

console.log(f5([3, 4]))
console.log(f5())

console.log("=== Mixed object and array destructuring ===")

function f6({name}, [score]) {
  return name + ":" + score
}

console.log(f6({name: "Alice"}, [95]))

# Array.prototype.pop()

**Status: IMPLEMENTED**

## Description

The `pop()` method of Array instances removes the last element from an array and returns that element. This method changes the length of the array.

## Usage

```js
const plants = ["broccoli", "cauliflower", "cucumber", "kale", "tomato"];

const lastPlant = plants.pop();
console.log(lastPlant);
// Expected output: "tomato"

console.log(plants.length);
// Expected output: 4
```

## Syntax

```
pop()
```

### Return value

The removed element from the array. `undefined` if the array is empty.

## Behavior

- If the array is empty, returns `undefined`.
- If the argument is not an array, returns `undefined`.
- If no arguments are passed, returns `undefined`.
- Removes and returns the last element of the array.
- Reduces the array length by 1.

## Relevant files

- `src/builtins/array/pop.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`

# Array.prototype.push()

**Status: IMPLEMENTED**

## Description

The `push()` method of Array instances adds one or more elements to the end of an array and returns the new length of the array.

## Usage

```js
const animals = ["pigs", "goats", "sheep"];

const count = animals.push("cows");
console.log(count);
// Expected output: 4

console.log(animals);
// Expected output: Array ["pigs", "goats", "sheep", "cows"]
```

## Syntax

```
push(element1)
push(element1, element2)
push(element1, element2, /* …, */ elementN)
```

### Parameters

- `element1, …, elementN` — The elements to add to the end of the array.

### Return value

The new length of the array.

## Behavior

- If less than 2 arguments are passed (missing the array), returns 0.
- If the first argument is not an array, returns 0.
- If no arguments are passed, returns 0.
- Adds one or more elements to the end of the array.
- Returns the new length of the array.

## Relevant files

- `src/builtins/array/push.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`

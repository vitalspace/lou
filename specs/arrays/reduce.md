# Array.prototype.reduce()

**Status: IMPLEMENTED**

## Description

The `reduce()` method of Array instances executes a reducer function on each element of the array, resulting in a single output value.

## Usage

```js
const array1 = [1, 2, 3, 4];

const initialValue = 0;
const sumWithInitial = array1.reduce(
  (accumulator, currentValue) => accumulator + currentValue,
  initialValue,
);

console.log(sumWithInitial);
// Expected output: 10
```

## Syntax

```
reduce(callbackFn)
reduce(callbackFn, initialValue)
```

### Parameters

- `callbackFn` — A function to execute for each element, taking four arguments: `accumulator`, `currentValue`, `currentIndex` (optional), and `array` (optional).
- `initialValue` (Optional) — A value to use as the first argument to the first call of `callbackFn`.

### Return value

The value that results from running the reducer function across the entire array.

## Relevant files

- `src/builtins/array/reduce.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`

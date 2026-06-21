# Array.prototype.reduceRight()

**Status: IMPLEMENTED**

## Description

The `reduceRight()` method of Array instances executes a reducer function on each element of the array from right to left, resulting in a single output value.

## Usage

```js
const array1 = [[0, 1], [2, 3], [4, 5]];

const result = array1.reduceRight((accumulator, currentValue) =>
  accumulator.concat(currentValue),
);

console.log(result);
// Expected output: Array [4, 5, 2, 3, 0, 1]
```

## Syntax

```
reduceRight(callbackFn)
reduceRight(callbackFn, initialValue)
```

### Parameters

- `callbackFn` — A function to execute for each element, taking four arguments: `accumulator`, `currentValue`, `currentIndex` (optional), and `array` (optional).
- `initialValue` (Optional) — A value to use as the first argument to the first call of `callbackFn`.

### Return value

The value that results from running the reducer function across the entire array.

## Relevant files

- `src/builtins/array/reduceRight.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`

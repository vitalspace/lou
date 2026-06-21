# Array.prototype.forEach()

**Status: IMPLEMENTED**

## Description

The `forEach()` method of Array instances executes a provided function once for each array element in order.

## Usage

```js
const array1 = ["a", "b", "c"];

array1.forEach((element) => console.log(element));
// Expected output: "a"
// Expected output: "b"
// Expected output: "c"
```

## Syntax

```
forEach(callbackFn)
forEach(callbackFn, thisArg)
```

### Parameters

- `callbackFn` — A function to execute for each element in the array, taking three arguments: `element`, `index` (optional), and `array` (optional).
- `thisArg` (Optional) — A value to use as `this` when executing `callbackFn`.

### Return value

`undefined`.

## Relevant files

- `src/builtins/array/forEach.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`

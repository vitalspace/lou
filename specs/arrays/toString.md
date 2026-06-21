# Array.prototype.toString()

**Status: IMPLEMENTED**

## Description

The `toString()` method of Array instances returns a string representing the array.

## Usage

```js
const array1 = [1, 2, "a", "1a"];

console.log(array1.toString());
// Expected output: "1,2,a,1a"
```

## Syntax

```
toString()
```

### Return value

A string representing the elements of the array separated by commas.

## Relevant files

- `src/builtins/array/toString.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`

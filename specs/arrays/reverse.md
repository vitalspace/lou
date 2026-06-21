# Array.prototype.reverse()

**Status: IMPLEMENTED**

## Description

The `reverse()` method of Array instances reverses the order of the elements of an array and returns the reversed array.

## Usage

```js
const array1 = ["one", "two", "three"];

console.log("array1:", array1);
// Expected output: Array ["one", "two", "three"]

const reversed = array1.reverse();

console.log("reversed:", reversed);
// Expected output: Array ["three", "two", "one"]
```

## Syntax

```
reverse()
```

### Return value

The reversed array.

## Relevant files

- `src/builtins/array/reverse.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`

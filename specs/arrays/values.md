# Array.prototype.values()

**Status: IMPLEMENTED**

## Description

The `values()` method of Array instances returns a new array iterator object that contains the values for each element in the array.

## Usage

```js
const array = ["a", "b", "c"];

const iterator = array.values();

for (const value of iterator) {
  console.log(value);
}
// Expected output: "a"
// Expected output: "b"
// Expected output: "c"
```

## Syntax

```
values()
```

### Parameters

None.

### Return value

A new array iterator object.

## Relevant files

- `src/builtins/array/values.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`

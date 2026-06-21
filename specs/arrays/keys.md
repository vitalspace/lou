# Array.prototype.keys()

**Status: IMPLEMENTED**

## Description

The `keys()` method of Array instances returns a new array iterator object that contains the keys (indices) for each element in the array.

## Usage

```js
const array = ["a", "b", "c"];

const iterator = array.keys();

for (const key of iterator) {
  console.log(key);
}
// Expected output: 0
// Expected output: 1
// Expected output: 2
```

## Syntax

```
keys()
```

### Parameters

None.

### Return value

A new array iterator object.

## Relevant files

- `src/builtins/array/keys.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`

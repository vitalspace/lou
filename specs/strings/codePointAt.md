# String.prototype.codePointAt()

**Status: IMPLEMENTED**

## Description

The `codePointAt()` method of String instances returns a non-negative integer that is the UTF-16 code point value at the given position.

## Usage

```js
const icons = "abc";

console.log(icons.codePointAt(1));
// Expected output: 98

console.log("abc".codePointAt(0));
// Expected output: 97

console.log("xyz".codePointAt(42));
// Expected output: undefined
```

## Syntax

```
codePointAt(pos)
```

### Parameters

- `pos` — Zero-based index of the character to be returned.

### Return value

A non-negative integer representing the code point value of the character at the given `pos`. Returns `undefined` if there is no element at `pos`.

## Behavior

- If `pos` is negative or greater than/equal to the string length, returns `undefined`.
- Handles characters outside the Basic Multilingual Plane (surrogate pairs) correctly.

## Relevant files

- `src/builtins/string/codePointAt.zig`


## Tests

> Tests need to be implemented for this method.

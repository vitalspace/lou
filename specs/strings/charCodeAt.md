# String.prototype.charCodeAt()

**Status: IMPLEMENTED**

## Description

The `charCodeAt()` method of String instances returns an integer between 0 and 65535 representing the UTF-16 code unit at the given index.

## Usage

```js
const sentence = "The quick brown fox jumps over the lazy dog.";

const index = 4;
console.log(`The character code ${index} is ${sentence.charCodeAt(index)}`);
// Expected output: "The character code 4 is 113"
// 113 is the UTF-16 value for "q"
```

## Syntax

```
charCodeAt()
charCodeAt(index)
```

### Parameters

- `index` — Zero-based index of the character to be returned. Constrained between 0 and `str.length - 1`. Defaults to 0 if not provided.

### Return value

A number between 0 and 65535 representing the UTF-16 code unit value at the given index. Returns `NaN` if the index is out of range.

## Behavior

- If `index` is not provided, defaults to 0.
- If `index` is negative or greater than/equal to the string length, returns `NaN`.
- Returns an integer representing the UTF-16 code unit value.

## Relevant files

- `src/builtins/string/charCodeAt.zig`


## Tests

> Tests need to be implemented for this method.

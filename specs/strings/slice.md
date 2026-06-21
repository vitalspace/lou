# String.prototype.slice()

**Status: IMPLEMENTED**

## Description

The `slice()` method of String instances extracts a section of this string and returns it as a new string, without modifying the original string.

## Usage

```js
const str = "The quick brown fox jumps over the lazy dog.";

console.log(str.slice(31));
// Expected output: "the lazy dog."

console.log(str.slice(4, 19));
// Expected output: "quick brown fox"

console.log(str.slice(-4));
// Expected output: "dog."

console.log(str.slice(-9, -5));
// Expected output: "lazy"
```

## Syntax

```
slice(indexStart)
slice(indexStart, indexEnd)
```

### Parameters

- `indexStart` — The index of the first character to include in the returned substring.
- `indexEnd` — The index of the first character to exclude from the returned substring.

### Return value

A new string containing the extracted section of the string.

## Behavior

- If `indexStart` is omitted, undefined, or cannot be converted to a number, extraction starts from index 0.
- If negative, it is treated as `str.length + indexStart`.
- If `indexStart >= str.length`, an empty string is returned.
- If `indexEnd` is omitted, undefined, or cannot be converted to a number, it extracts to the end of the string.
- If negative, it is treated as `str.length + indexEnd`.
- Characters are extracted up to but not including `indexEnd`.

## Relevant files

- `src/builtins/string/slice.zig`


## Tests

> Tests need to be implemented for this method.

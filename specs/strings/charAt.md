# String.prototype.charAt()

**Status: IMPLEMENTED**

## Description

The `charAt()` method of String instances returns a new string consisting of the single UTF-16 code unit at the given index.

## Usage

```js
const sentence = "The quick brown fox jumps over the lazy dog.";

const index = 4;
console.log(`The character at index ${index} is ${sentence.charAt(index)}`);
// Expected output: "The character at index 4 is q"
```

## Syntax

```
charAt()
charAt(index)
```

### Parameters

- `index` — Zero-based index of the character to be returned. Constrained between 0 and `str.length - 1`. Defaults to 0 if not provided.

### Return value

A string representing the character at the specified index, or an empty string if the index is out of range.

## Behavior

- If `index` is not provided, defaults to 0.
- If `index` is negative or greater than/equal to the string length, returns an empty string.
- Returns a string of length 1.

## Relevant files

- `src/builtins/string/charAt.zig`


## Tests

> Tests need to be implemented for this method.

# String.prototype.substring()

**Status: IMPLEMENTED**

## Description

The `substring()` method of String instances returns the part of this string from the start index up to and excluding the end index, or to the end of the string if no end index is supplied.

## Usage

```js
const str = "Mozilla";

console.log(str.substring(1, 3));
// Expected output: "oz"

console.log(str.substring(2));
// Expected output: "zilla"
```

## Syntax

```
substring(indexStart)
substring(indexStart, indexEnd)
```

### Parameters

- `indexStart` — The index of the first character to include in the returned substring.
- `indexEnd` — The index of the first character to exclude from the returned substring.

### Return value

A new string containing the specified part of the given string.

## Behavior

- If either argument is `NaN` or negative, it is replaced by 0.
- If either argument is greater than `str.length`, it is treated as `str.length`.
- If `indexStart > indexEnd`, the arguments are swapped.

## Relevant files

- `src/builtins/string/substring.zig`


## Tests

> Tests need to be implemented for this method.

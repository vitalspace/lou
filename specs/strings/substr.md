# String.prototype.substr()

**Status: IMPLEMENTED**

## Description

The `substr()` method of String instances returns a portion of this string, starting at the specified index and extending for a given number of characters afterwards.

> **Note:** `substr()` is not part of the main ECMAScript specification — it is defined in Annex B. Consider using `substring()` or `slice()` instead.

## Usage

```js
const str = "Mozilla";

console.log(str.substr(1, 2));
// Expected output: "oz"

console.log(str.substr(2));
// Expected output: "zilla"
```

## Syntax

```
substr(start)
substr(start, length)
```

### Parameters

- `start` — The index of the first character to include in the returned substring.
- `length` — The number of characters to extract.

### Return value

A new string containing the specified part of the given string.

## Behavior

- If `start` is positive and >= `str.length`, returns an empty string.
- If `start` is negative, it is treated as `str.length + start`.
- If `length` is 0 or negative, returns an empty string.
- If `length` is omitted, extracts to the end of the string.

## Relevant files

- `src/builtins/string/substr.zig`


## Tests

> Tests need to be implemented for this method.

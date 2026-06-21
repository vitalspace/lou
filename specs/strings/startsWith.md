# String.prototype.startsWith()

**Status: IMPLEMENTED (limited — byte-level, not codepoint-aware)**

## Description

The `startsWith()` method of String instances determines whether this string begins with the characters of a specified string, returning `true` or `false` as appropriate.

## Usage

```js
const str = "Saturday night plans";

console.log(str.startsWith("Sat"));
// Expected output: true

console.log(str.startsWith("Sat", 3));
// Expected output: false
```

## Syntax

```
startsWith(searchString)
startsWith(searchString, position)
```

### Parameters

- `searchString` — The characters to be searched for at the beginning of this string. Cannot be a regex.
- `position` — The position in this string at which to begin searching for `searchString`. Defaults to 0.

### Return value

`true` if the given characters are found at the beginning of the string, including when `searchString` is an empty string; otherwise `false`.

## Behavior

- Case-sensitive comparison.
- If `searchString` is an empty string, returns `true`.
- If `position` is negative, it is treated as 0.

## Relevant files

- `src/builtins/string/startsWith.zig`


## Tests

> Tests need to be implemented for this method.

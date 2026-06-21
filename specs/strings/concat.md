# String.prototype.concat()

**Status: IMPLEMENTED**

## Description

The `concat()` method of String instances concatenates the string arguments to this string and returns a new string.

## Usage

```js
const str1 = "Hello";
const str2 = "World";

console.log(str1.concat(" ", str2));
// Expected output: "Hello World"

console.log("".concat("a", "b", "c"));
// Expected output: "abc"
```

## Syntax

```
concat(str1)
concat(str1, str2)
concat(str1, str2, /* …, */ strN)
```

### Parameters

- `str1, …, strN` — One or more strings to concatenate to this string.

### Return value

A new string containing the combined text of the provided strings.

## Behavior

- Does not modify the original string (strings are immutable).
- If no arguments are provided, returns a string equal to the original.
- Non-string arguments are converted to strings.

## Relevant files

- `src/builtins/string/concat.zig`


## Tests

> Tests need to be implemented for this method.

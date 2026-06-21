# String.prototype.padEnd()

**Status: IMPLEMENTED**

## Description

The `padEnd()` method of String instances pads this string with another string (multiple times, if needed) until the resulting string reaches the given length. The padding is applied from the end of this string.

## Usage

```js
const str = "Breaded Mushrooms";

console.log(str.padEnd(25, "."));
// Expected output: "Breaded Mushrooms........"

console.log(str.padEnd(25));
// Expected output: "Breaded Mushrooms        "

console.log("abc".padEnd(1));
// Expected output: "abc"
```

## Syntax

```
padEnd(targetLength)
padEnd(targetLength, padString)
```

### Parameters

- `targetLength` — The length of the resulting string once the current string has been padded. If `targetLength` is less than or equal to the length of the current string, the current string is returned as-is.
- `padString` — The string to pad the current string with. Defaults to `" "` (space).

### Return value

A String of the specified `targetLength` with the `padString` applied at the end of the given string.

## Behavior

- If `padString` is too long to fit within `targetLength`, it will be truncated from the end.
- If the current string is already longer than `targetLength`, the string is returned unchanged.

## Relevant files

- `src/builtins/string/padEnd.zig`


## Tests

> Tests need to be implemented for this method.

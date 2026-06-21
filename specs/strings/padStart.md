# String.prototype.padStart()

**Status: IMPLEMENTED**

## Description

The `padStart()` method of String instances pads this string with another string (multiple times, if needed) until the resulting string reaches the given length. The padding is applied from the start of this string.

## Usage

```js
const str = "5";

console.log(str.padStart(2, "0"));
// Expected output: "05"

const fullNumber = "2034399002125581";
const last4 = fullNumber.slice(-4);
const masked = last4.padStart(fullNumber.length, "*");

console.log(masked);
// Expected output: "************5581"
```

## Syntax

```
padStart(targetLength)
padStart(targetLength, padString)
```

### Parameters

- `targetLength` — The length of the resulting string once the current string has been padded. If `targetLength` is less than or equal to the length of the current string, the current string is returned as-is.
- `padString` — The string to pad the current string with. Defaults to `" "` (space).

### Return value

A String of the specified `targetLength` with the `padString` applied at the start of the given string.

## Behavior

- If `padString` is too long to fit within `targetLength`, it will be truncated from the end.
- If the current string is already longer than `targetLength`, the string is returned unchanged.

## Relevant files

- `src/builtins/string/padStart.zig`


## Tests

> Tests need to be implemented for this method.

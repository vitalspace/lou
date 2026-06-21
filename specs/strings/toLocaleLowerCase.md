# String.prototype.toLocaleLowerCase()

**Status: IMPLEMENTED (limited — Turkish locale only, no ICU)**

## Description

The `toLocaleLowerCase()` method of String instances returns this string converted to lower case, according to any locale-specific case mappings.

## Usage

```js
const city = "istanbul";

console.log(city.toLocaleLowerCase());
// Expected output: "istanbul"

console.log("ISTANBUL".toLocaleLowerCase("en-US"));
// Expected output: "istanbul"
```

## Syntax

```
toLocaleLowerCase()
toLocaleLowerCase(locales)
```

### Parameters

- `locales` — A string with a BCP 47 language tag, or an array of such strings.

### Return value

A new string representing this string converted to lower case, according to any locale-specific case mappings.

## Behavior

- In most cases, this produces the same result as `toLowerCase()`.
- For certain locales (e.g., Turkish), the result may differ.

## Implementation notes

- Lou implements Turkish/Azerbaijani locale detection (`tr`/`az`) for the `I` → `ı` (U+0131) rule. This is the most common case where locale-aware lowercasing differs from simple ASCII lowercasing.
- Lou does **not** bundle ICU. Full locale-aware case mapping requires the Unicode case folding tables (~25MB with ICU). Only the Turkish dotted/dotless I rule is hardcoded.
- For all other locales, this function behaves identically to `toLowerCase()`. Characters outside ASCII (e.g., `İ` → `i` in Turkish) are not handled.

## Relevant files

- `src/builtins/string/toLocaleLowerCase.zig`


## Tests

> Tests need to be implemented for this method.

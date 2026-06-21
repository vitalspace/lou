# String.prototype.toLocaleUpperCase()

**Status: IMPLEMENTED (limited — Turkish locale only, no ICU)**

## Description

The `toLocaleUpperCase()` method of String instances returns this string converted to upper case, according to any locale-specific case mappings.

## Usage

```js
const city = "istanbul";

console.log(city.toLocaleUpperCase());
// Expected output: "ISTANBUL"

console.log("istanbul".toLocaleUpperCase("en-US"));
// Expected output: "ISTANBUL"
```

## Syntax

```
toLocaleUpperCase()
toLocaleUpperCase(locales)
```

### Parameters

- `locales` — A string with a BCP 47 language tag, or an array of such strings.

### Return value

A new string representing this string converted to upper case, according to any locale-specific case mappings.

## Behavior

- In most cases, this produces the same result as `toUpperCase()`.
- For certain locales (e.g., Turkish), the result may differ.

## Implementation notes

- Lou implements Turkish/Azerbaijani locale detection (`tr`/`az`) for the `i` → `İ` (U+0130) rule. This is the most common case where locale-aware uppercasing differs from simple ASCII uppercasing.
- Lou does **not** bundle ICU. Full locale-aware case mapping requires the Unicode case folding tables (~25MB with ICU). Only the Turkish dotted/dotless I rule is hardcoded.
- For all other locales, this function behaves identically to `toUpperCase()`. Characters outside ASCII (e.g., `ß` → `SS` in German) are not handled.

## Relevant files

- `src/builtins/string/toLocaleUpperCase.zig`


## Tests

> Tests need to be implemented for this method.

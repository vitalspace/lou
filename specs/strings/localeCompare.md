# String.prototype.localeCompare()

**Status: IMPLEMENTED (limited — no ICU, byte-level comparison)**

## Description

The `localeCompare()` method of String instances returns a number indicating whether this string comes before, after, or is the same as the given string in sort order.

## Usage

```js
const a = "réservé";
const b = "RESERVE";

console.log(a.localeCompare(b));
// Expected output: a negative value (in most locales)
```

## Syntax

```
localeCompare(compareString)
localeCompare(compareString, locales)
localeCompare(compareString, locales, options)
```

### Parameters

- `compareString` — The string against which the `str` is compared.
- `locales` — A string with a BCP 47 language tag, or an array of such strings.
- `options` — An object with configuration properties.

### Return value

A negative number if `str` occurs before `compareString`; positive if it occurs after; `0` if they are equivalent.

## Behavior

- The comparison is locale-sensitive.
- The result is implementation-defined if no locale is specified.

## Implementation notes

- Lou does **not** bundle ICU (International Components for Unicode).
- The comparison is byte-level (`std.mem.order(u8, ...)`), which works correctly for ASCII but may give incorrect results for non-ASCII characters (e.g., `"ä".localeCompare("z")` should return `-1` in en-US but Lou returns `1` because `0xC3 > 0x7A`).
- Adding ICU would add ~25MB to the binary, which is disproportionate for Lou's scope.
- Engines like V8, SpiderMonkey, and JavaScriptCore all link ICU for proper locale-aware collation.

## Relevant files

- `src/builtins/string/localeCompare.zig`


## Tests

> Tests need to be implemented for this method.

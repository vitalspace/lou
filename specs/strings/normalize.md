# String.prototype.normalize()

**Status: IMPLEMENTED (limited — Latin-1 Supplement table only, no ICU)**

## Description

The `normalize()` method of String instances returns the Unicode Normalization Form of this string.

## Usage

```js
const name1 = "\u0041\u006d\u00e9\u006c\u0069\u0065";
const name2 = "\u0041\u006d\u0065\u0301\u006c\u0069\u0065";

console.log(`${name1}, ${name2}`);
// Expected output: "Amélie, Amélie"

console.log(name1 === name2);
// Expected output: false

console.log(name1.normalize("NFC") === name2.normalize("NFC"));
// Expected output: true
```

## Syntax

```
normalize()
normalize(form)
```

### Parameters

- `form` — One of `"NFC"`, `"NFD"`, `"NFKC"`, or `"NFKD"`. Defaults to `"NFC"`.

### Return value

A string containing the Unicode Normalization Form of the given string.

## Behavior

- `"NFC"` — Canonical Decomposition, followed by Canonical Composition.
- `"NFD"` — Canonical Decomposition.
- `"NFKC"` — Compatibility Decomposition, followed by Canonical Composition.
- `"NFKD"` — Compatibility Decomposition.

## Implementation notes

- Lou uses a **hardcoded decomposition/composition table** covering only Latin-1 Supplement characters (U+00C0–U+00FF). This handles common accented Latin characters like é, ü, ñ, etc.
- Lou does **not** bundle ICU. The full Unicode normalization database includes decomposition mappings for ~40,000+ codepoints and requires ~25MB of data.
- Characters outside the Latin-1 Supplement range (e.g., CJK, Cyrillic, Greek, Arabic) are passed through unchanged in all normalization forms.

## Relevant files

- `src/builtins/string/normalize.zig`


## Tests

> Tests need to be implemented for this method.

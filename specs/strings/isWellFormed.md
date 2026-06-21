# String.prototype.isWellFormed()

**Status: IMPLEMENTED**

## Description

The `isWellFormed()` method of String instances returns a boolean indicating whether this string contains any lone surrogates.

## Usage

```js
const str1 = "hello\uD800";
console.log(str1.isWellFormed());
// Expected output: false

const str2 = "hello";
console.log(str2.isWellFormed());
// Expected output: true
```

## Syntax

```
isWellFormed()
```

### Parameters

None.

### Return value

`true` if the string does not contain any lone surrogates; `false` otherwise.

## Behavior

- Returns `true` for well-formed strings (no lone surrogates).
- Returns `false` if the string contains unpaired surrogates.
- Strings with valid surrogate pairs (high + low) are well-formed.
- Empty string is well-formed.

## Additional Examples

```js
// Normal ASCII string is well-formed
"hello".isWellFormed();
// Expected output: true

// Empty string is well-formed
"".isWellFormed();
// Expected output: true

// String with lone surrogate at end
"abc\uD800".isWellFormed();
// Expected output: false

// String with lone surrogate at start
"\uDC00abc".isWellFormed();
// Expected output: false

// String with multiple lone surrogates
"\uD800\uD800\uD800".isWellFormed();
// Expected output: false

// String with valid surrogate pair (emoji)
"\uD83D\uDE00".isWellFormed();
// Expected output: true

// String with lone high surrogate in middle
"a\uD800b".isWellFormed();
// Expected output: false
```

## Relevant files

- `src/builtins/string/isWellFormed.zig`


## Tests

> Tests need to be implemented for this method.

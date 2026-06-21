# String.prototype.at()

**Status: IMPLEMENTED**

## Description

The `at()` method of String instances takes an integer value and returns a new String consisting of the single UTF-16 code unit located at the specified offset. This method allows for positive and negative integers. Negative integers count back from the last string character.

## Usage

```js
const sentence = "The quick brown fox jumps over the lazy dog.";

const index = 5;

console.log(`An index of ${index} returns the character ${sentence.at(index)}`);
// Expected output: "An index of 5 returns the character u"

const index2 = -4;

console.log(`An index of ${index2} returns the character ${sentence.at(index2)}`);
// Expected output: "An index of -4 returns the character d"
```

## Syntax

```
at(index)
```

### Parameters

- `index` — Zero-based index of the string character to be returned. Negative integers count back from the last character.

### Return value

The character located at the specified index, or `undefined` if the index is out of range.

## Behavior

- Accepts positive and negative integer values.
- Negative integers count back from the last character.
- Returns `undefined` if the index is out of range.
- Equivalent to `str[index]` for positive indices, but supports negative indexing.

## Relevant files

- `src/builtins/string/at.zig`


## Tests

> Tests need to be implemented for this method.

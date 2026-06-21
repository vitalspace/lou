# String.prototype.repeat()

**Status: IMPLEMENTED**

## Description

The `repeat()` method of String instances constructs and returns a new string which contains the specified number of copies of this string, concatenated together.

## Usage

```js
const chorus = "Because I'm happy. ";

console.log(`Chorus lyrics for "Happy": ${chorus.repeat(2)}`);
// Expected output: "Chorus lyrics for "Happy": Because I'm happy. Because I'm happy. "
```

## Syntax

```
repeat(count)
```

### Parameters

- `count` — An integer between 0 and `+Infinity`, indicating the number of times to repeat the string.

### Return value

A new string containing the specified number of copies of the given string.

## Behavior

- If `count` is 0, returns an empty string.
- If `count` is negative or `Infinity`, throws a `RangeError`.

## Relevant files

- `src/builtins/string/repeat.zig`


## Tests

> Tests need to be implemented for this method.

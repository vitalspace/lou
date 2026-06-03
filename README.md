# Lou

<img width="400" height="400" alt="157634247" src="https://github.com/user-attachments/assets/14eb6160-7670-4325-80cb-c83b1f75c266" />

A scripting language with partial JavaScript/TypeScript support, written in Zig.

## Features

- JavaScript/TypeScript-like syntax
- Built-in objects: `console`, `Math`, `JSON`, `Set`, `Map`, `Object`, `Array`, `String`, `RegExp`
- Type checker
- Bytecode VM with optimizations
- Fast execution via Zig

## Requirements

- Zig 0.16

## Installation

```bash
git clone https://github.com/your-username/lou.git
cd lou
zig build
```

## Usage

```bash
lou run <filename>
```

## Build

```bash
zig build          # Debug build
zig build release  # ReleaseFast build
zig build test     # Run tests
zig build run      # Run the app
```

## Builtins

### Console
`console.log()`, `console.error()`, `console.clear()`, `console.time()`

### Math
`Math.abs()`

### String
`charAt()`, `charCodeAt()`, `codePointAt()`, `concat()`, `endsWith()`, `includes()`, `indexOf()`, `lastIndexOf()`, `localeCompare()`, `match()`, `matchAll()`, `normalize()`, `padEnd()`, `padStart()`, `repeat()`, `replace()`, `replaceAll()`, `search()`, `slice()`, `split()`, `startsWith()`, `substr()`, `substring()`, `toLowerCase()`, `toUpperCase()`, `trim()`, `trimEnd()`, `trimStart()`, `toString()`, `valueOf()`

### Array
`push()`, `pop()`, `at()`, `concat()`, `copyWithin()`, `entries()`, `every()`, `fill()`, `filter()`, `find()`, `findIndex()`, `length()`, `toSorted()`, `toReversed()`, `toSpliced()`

### Set & Map
Full implementation with methods: `add()`, `has()`, `delete()`, `clear()`, `size()`, `forEach()`, `entries()`, `keys()`, `values()`, `toString()`

### Object
`Object.assign()`, `Object.create()`, `Object.entries()`, `Object.hasOwn()`, `Object.keys()`, `Object.values()`

### JSON
`JSON.stringify()`

### RegExp
Full regex engine with parser, compiler, and VM

## Architecture

```
src/
├── main.zig           # Entry point
├── lexer.zig          # Tokenizer
├── parser.zig         # AST generation
├── ast.zig            # AST definitions
├── evaluator.zig      # Tree-walking evaluator
├── vm.zig             # Bytecode VM
├── type_checker.zig   # Type checking
├── environment.zig    # Variable scope
├── optimizations.zig  # Optimizer
├── builtins/          # Built-in functions
│   ├── console/
│   ├── string/
│   ├── array/
│   ├── set/
│   ├── map/
│   ├── object/
│   ├── math/
│   ├── regex/
│   └── json/
└── types/             # Runtime types
```

## Philosophy

Lou will never abandon Zig development; if for any reason Zig lacks something for Lou to be fast and efficient, we will use interoperability with C/C++.

# `for...of` loop

**Prioridad: media** — ✅ COMPLETADO

## Estado

| Componente | Archivo | Estado |
|---|---|---|
| Lexer (token `Of`) | `src/lexer.zig` | ✅ |
| AST (`ForOfLoop`) | `src/ast.zig` | ✅ |
| Parser (`for (x of iter)`) | `src/parser.zig` | ✅ |
| Evaluador | `src/evaluator.zig` | ✅ |
| VM | `src/vm.zig` | ✅ |

### Soporta

- `for (var/let/const x of array)` ✅
- `for (var/let/const x of string)` ✅
- `for (var/let/const x of Set)` ✅
- `for (var/let/const x of Map)` ✅
- `for (var/let/const x of generator)` ✅
- `for (var/let/const x of .values()/.keys()/.entries())` ✅
- Yield dentro del body con re-entry ✅

## Referencia

- `src/parser.zig` — parsing de `for...of`
- `src/ast.zig` — nodo `ForOfLoop`
- `src/evaluator.zig` — evaluación de `ForOfLoop`
- `src/vm.zig` — compilación/interpretación de `ForOfLoop`
- `specs/todos/symbol-well-known.md` — dependencia de `Symbol.iterator`

## Verificación

```js
var arr = [1, 2, 3];
var sum = 0;
for (const x of arr) { sum += x; }
console.log(sum); // 6

var s = Set([10, 20, 30]);
var result = [];
for (const v of s) { result.push(v); }
console.log(result); // [10, 20, 30]

var m = Map([["a", 1], ["b", 2]]);
var keys = [];
for (const [k, v] of m) { keys.push(k); }
console.log(keys); // ["a", "b"]

for (const c of "hello") { console.log(c); } // h, e, l, l, o
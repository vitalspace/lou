# Sparse array handling ✅

~~**Prioridad: media**~~ **Resuelto**

## Problema

Los métodos de array en lou no manejan holes (elementos vacíos) correctamente. En Node.js, un sparse array como `[1,,3]` trata el elemento vacío como `undefined` en algunos métodos y lo salta en otros.

## Contexto

- ECMAScript especifica que métodos como `forEach`, `map`, `filter`, etc. NO ejecutan el callback para holes
- Métodos como `find`, `findIndex`, `includes` SÍ iteran sobre holes (los ven como `undefined`)
- En lou, todos los arrays son densos — no hay concepto de "hole"

## Implementación

- `src/types/runtime.zig`: nuevo `.hole` en `Value` union; `set()` llena gaps con `.hole` (no `0.0`); `ArrayIterator` convierte `.hole` → `.void`
- `src/ast.zig`: nuevo nodo `Elision` en AST; `freeAst` y `printAst` lo manejan
- `src/parser.zig`: `parseArrayLiteral` soporta elisiones (`[1,,3]`)
- `src/evaluator.zig`: `ArrayLiteral` emite `.hole` para `Elision`; `ArrayIndex` devuelve `.void` para holes; `valuesEqual` trata `.hole == .void`
- `src/vm.zig`: `truthy`, `valEq`, `valToStr` manejan `.hole`; `expr()` emite `.hole` para `Elision`
- `src/environment.zig`: `freeValue` maneja `.hole`
- `src/builtins/builtins.zig`: `Array(N)` usa `.hole`
- `src/builtins/console/log.zig`, `error.zig`: muestran `<empty>` para holes
- `src/builtins/array/forEach.zig`, `map.zig`, `filter.zig`, `some.zig`, `every.zig`: saltan holes
- `src/builtins/array/map.zig`: preserva `.hole` en resultado
- `src/builtins/array/find.zig`, `findIndex.zig`, `findLast.zig`, `findLastIndex.zig`: pasan `.void` al callback para holes
- `src/builtins/array/includes.zig`: `valEq(.hole, .void)` → true (ve holes como undefined)
- `src/builtins/array/indexOf.zig`, `lastIndexOf.zig`: saltan holes (como especifica ECMAScript)
- `src/builtins/array/flat.zig`, `flatMap.zig`: saltan holes
- `src/builtins/array/reduce.zig`, `reduceRight.zig`: saltan holes; primer elemento no-hole como accumulator inicial

## Referencia

- `specs/arrays/every.md`, `filter.md`, `find.md`, `findIndex.md`, `forEach.md`, `map.md`, `some.md`
- `specs/arrays/includes.md`, `indexOf.md`, `lastIndexOf.md`

## Verificación

- `[1,,3].forEach(x => console.log(x))` loguea solo `1` y `3` (no `undefined`) ✅
- `[1,,3].find(x => x === undefined)` encuentra el hole ✅
- `[1,,3].map(x => x * 2)` → `[2, <hole>, 6]` (mapped[1] es undefined) ✅
- `[1,,3].includes(undefined)` → `true` ✅
- `[1,,3].indexOf(undefined)` → `-1` (indexOf salta holes) ✅
- `[1,,3].flat()` → `[1, 3]` ✅
- `Array(3)` → `[<hole>, <hole>, <hole>]` (arr[0] es undefined) ✅
- `[,,3][0]` → `undefined` ✅
- `[1,,3].reduce((a, x) => a + x, 0)` → `4` ✅

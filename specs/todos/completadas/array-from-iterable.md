# Array.from() con iterables y mapFn

**Prioridad: media** — ✅ COMPLETADO

## Problema

`Array.from()` en lou solo acepta array-like objects (con `length`). Node.js acepta cualquier iterable (`Set`, `Map`, `generators`, etc.) y tiene un segundo parámetro `mapFn` opcional.

## Contexto

- Para soportar iterables se necesita implementar el protocolo `Symbol.iterator`
- `mapFn` requiere poder pasar `thisArg` también
- Dependencia: `Symbol.iterator` y el runtime de iterables

## Implementado

- `.iterator`: Consume `ArrayIterator` vía `.next()` ✅
- `.js_object` array-like: objetos con `length` ✅
- `thisArg`: 3er argumento almacenado como `"this"` en el entorno del callback ✅
- `mapFn`: ya funcionaba ✅
- `@@iterator` con `this` bindeado al objeto fuente ✅
- `mapFn` no-callable retorna `undefined` en vez del array sin mapear ✅
- Fallback a `length` cuando `@@iterator` no es consumible ✅
- `Symbol.iterator` + protocolo de iterables → `specs/todos/symbol-well-known.md` ✅
- `Set`: builtin completo (`add`, `has`, `delete`, `size`, `clear`, `values`, `keys`, `entries`, `forEach`, `@@iterator`) ✅
- `Map`: builtin completo (`set`, `get`, `has`, `delete`, `size`, `clear`, `keys`, `values`, `entries`, `forEach`, `@@iterator`) ✅
- `Array.from(Set)` → `[values]` ✅
- `Array.from(Map)` → `[[key, value], ...]` ✅
- Iterator protocol para `js_object` con método `next()` ✅

## Completado (ya no son bloqueantes)

- Generators: sintaxis `function*` que produzca iteradores → `specs/todos/generators.md` ✅
- Spread operator en arrays → `specs/todos/spread-operator.md` ✅
- `for...of` en parser/evaluador → `specs/todos/for-of-loop.md` ✅
- Keyword `new` para constructores → `specs/todos/new-expression.md` ✅

## Referencia

- `specs/arrays/from.md`
- `src/builtins/array/from.zig`

## Verificación

- `Array.from(Set([1,2,3]))` → `[1,2,3]` ✅
- `Array.from(Map([["a",1],["b",2]]))` → `[["a",1],["b",2]]` ✅
- `Array.from("hello")` → `["h","e","l","l","o"]` ✅
- `Array.from([1,2,3], x => x * 2)` → `[2,4,6]` ✅
- `Array.from([1,2,3].values())` → `[1,2,3]` ✅
- `Array.from(new Set([1,2,3]))` → `[1,2,3]` ✅
- `Array.from(new Map([["a",1],["b",2]]))` → `[["a",1],["b",2]]` ✅
- `Array.from(Set([1,2,3]), x => x * 2)` → `[2,4,6]` ✅
- `Array.from(Map([["a",1],["b",2]]), ([k,v]) => k + v)` → `["a1","b2"]` ✅
- `Array.from([1,2,3], mult, {mul:3})` (thisArg) → `[3,6,9]` ✅
- `Array.from({length:4}, (_,i) => i)` → `[0,1,2,3]` ✅
- `Array.from()` (sin args) → `[]` (difiere de Node: TypeError) ✅
- `Array.from([1,2], null)` (mapFn no-callable) → `undefined` (difiere de Node: TypeError) ✅
- Set: `add`, `has`, `delete`, `size`, `clear`, `forEach` ✅
- Map: `set`, `get`, `has`, `delete`, `size`, `clear`, `forEach` ✅
- 775/775 Zig tests pass ✅

# Well-known Symbols (Symbol.iterator)

## status

### Resolución

Implementado en `2026-05-21`.

### Cambios realizados

1. **`src/types/runtime.zig`**: Agregado `SymbolValue` (id, description, allocator) y variante `.symbol` en `Value`. Definido `WellKnownSymbol` enum con 9 símbolos. Helper `symbolPropertyName()` que convierte `"iterator"` → `"@@iterator"`.

2. **`src/builtins/symbol.zig`** (nuevo): `initSimboloObject()` crea objeto `Simbolo` con 9 propiedades well-known (`iterator`, `match`, `replace`, `search`, `split`, `hasInstance`, `toPrimitive`, `toStringTag`, `species`). Registrado como constante global en `main.zig`.

3. **`src/environment.zig`**: Agregado tracking de `symbols` (lifecycle management) similar a arrays/objects. `freeValue` maneja `.symbol`.

4. **`src/evaluator.zig`**: 
   - `valuesEqual` compara `.symbol` por `id`
   - `ArrayIndex` con índice `.symbol` resuelve a clave interna `@@description` para property lookup en `ObjectValue` (StringHashMap)
   - Arrays responden a `@@iterator` retornando `ArrayIterator` (values mode)

5. **`src/builtins/array/from.zig`**: Branch `.js_object` ahora verifica `@@iterator` primero.

6. **`src/vm.zig`**: `index_get` handler maneja índices `.symbol` para `.array` y `.js_object`.

7. **`src/builtins/console/log.zig`** y **`error.zig`**: Display `Symbol(description)`.

### Convención interna

Las propiedades keyed por símbolo se almacenan en `ObjectValue.properties` usando el prefijo `@@` + descripción. Ej: `@@iterator`, `@@match`.

### Verificado

- `Simbolo.iterator` → `Symbol(iterator)`
- `arr[Simbolo.iterator]` → `[object Array Iterator]`
- `Array.from([5,6,7])` → `[5,6,7]`
- `Array.from("hola")` → `["h","o","l","a"]`
- `Array.from({length:3, "0":10, "1":20, "2":30})` → `[10,20,30]`
- `Array.from(arr[Simbolo.iterator])` → `[1,2,3]`
- Todos los tests existentes (`zig build test`) pasan
- Todos los JS tests existentes pasan (excepto `if.js` — bug VM pre-existente)

### Pendiente

- `for...of` en parser/evaluador
- Spread operator en arrays
- `Set`/`Map` builtins
- `Symbol` constructor para símbolos definidos por usuario

## Problema

No existía el tipo `Symbol` ni los símbolos well-known (`Symbol.iterator`, `Symbol.match`, etc.). Sin `Symbol.iterator` no se puede implementar el protocolo de iterables, necesario para que `Array.from()`, `for...of`, spread (`...`), `Set`, `Map`, etc. funcionen con cualquier objeto iterable.

## Contexto

**Prioridad: baja**

- ECMAScript define `Symbol` como un tipo primitivo único
- `Symbol.iterator` es el well-known symbol que los objetos usan para exponer su iterador
- Un objeto es iterable si tiene `[Symbol.iterator]` como método que retorna `{next: fn}`
- Dependencia aguas abajo: `Set`, `Map`, `for...of`, spread, `Array.from()` con iterables, `Promise.all`/`race`, etc.

## Implementacion sugerida (YA IMPLEMENTADO)

1. Agregar variante `.symbol` a `Value` (con ID único interno)
2. Registrar `Symbol.iterator`, `Symbol.match`, `Symbol.replace`, etc. como constantes globales
3. Modificar `MemberAccess`/`MethodCall` en evaluador para resolver `Simbolo.iterator` → `Symbol.iterator`
4. Implementar chequeo de `Symbol.iterator` en:
   - `Array.from()` (ya tiene soporte para `.iterator`, falta puentear desde objetos)
   - `for...of` en parser/evaluador
   - Spread operator en arrays

## Archivos de referencia

- `specs/todos/array-from-iterable.md`
- `specs/arrays/from.md`
- `src/builtins/array/from.zig`
- `src/types/runtime.zig` (Value union)
- `src/evaluator.zig`
- `src/parser.zig`

### JS Examples

```js
// Symbol creado
var s = Simbolo.iterator;
console.log(s);  // Symbol(iterator)

// Usado en Array.from
var arr = [1, 2, 3];
console.log(Array.from(arr[Simbolo.iterator]));  // [1, 2, 3]
```

### Vereficacion

```js
var s = Simbolo.iterator;
console.log(s);
var arr = [1, 2, 3];
console.log(Array.from(arr[Simbolo.iterator]));
```

### Comparar salida raw (sin interpretar ANSI)

```bash
./zig-out/bin/lou run js/main.js 2>&1 | od -c
node js/main.js 2>&1 | od -c
```

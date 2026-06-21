# `for...in` loop

## status

✅ COMPLETADO

## Problema

Lou no soportaba el statement `for...in` para iterar sobre las claves de un objeto. La implementación ya estaba parcialmente presente pero con errores de compilación (definición duplicada de `ForInLoop` en AST y tipo `ForOfVariable` sin definir).

## Contexto

**Prioridad: media**

El loop `for...in` itera sobre las claves enumerables de un objeto (o índices de array como strings). Se agregó soporte para este statement en lexer, parser, AST, evaluador y VM.

## Código que funciona

```js
var resumen = { Token: { LATAM: 120, USA: 200 } };

for (var producto in resumen) {
  console.log(producto); // "Token"
}

var keys = Object.keys(resumen); // alternativa
for (var i = 0; i < keys.length; i = i + 1) {
  console.log(keys[i]);
}
```

### Detalles de implementación

1. **AST** (`src/ast.zig`): Se eliminó la definición duplicada de `ForInLoop` y se cambió `ForOfVariable` (indefinido) a `[]const u8` tanto en `ForOfLoop` como `ForInLoop`
2. **Lexer** (`src/lexer.zig`): `token.In` ya existía y funciona sin cambios
3. **Parser** (`src/parser.zig`): Ya parseaba `for...in` correctamente
4. **Evaluador** (`src/evaluator.zig`): Ya evaluaba `ForInLoop` para objetos y arrays. Se corrigió bug de referencia a buffer stack-local en el caso de arrays (duplicar string con `allocator.dupe`). Se agregaron tests unitarios
5. **VM** (`src/vm.zig`): Ya compilaba `ForInLoop` mediante `eval_node` fallback

### Estado por componente

| Componente | Archivo | Estado |
|---|---|---|
| Lexer (token `In`) | `src/lexer.zig` | ✅ |
| Parser (`for (x in obj)`) | `src/parser.zig` | ✅ |
| AST (`ForInLoop`) | `src/ast.zig` | ✅ |
| Evaluador | `src/evaluator.zig` | ✅ |
| VM | `src/vm.zig` | ✅ |

## Archivos de referencia

- `specs/todos/for-of-loop.md` — patrón similar ya implementado
- `src/parser.zig` — parser de for loops
- `src/ast.zig` — nodo `ForOfLoop` como referencia
- `src/evaluator.zig` — evaluación de `ForOfLoop`
- `src/vm.zig` — compilación de `ForOfLoop`

### JS Examples

```js
var resumen = { Token: { LATAM: 120, USA: 200 } };

for (var producto in resumen) {
  console.log(producto); // "Token"
}

var keys = Object.keys(resumen); // alternativa temporal
for (var i = 0; i < keys.length; i = i + 1) {
  console.log(keys[i]);
}
```

```js
var obj = { a: 1, b: 2, c: 3 };
var keys = [];
for (var k in obj) { keys.push(k); }
console.log(keys); // ["a", "b", "c"]

var arr = [10, 20, 30];
var indices = [];
for (var idx in arr) { indices.push(idx); }
console.log(indices); // ["0", "1", "2"]

var numKeys = [];
for (var n in 12345) { numKeys.push(n); }
console.log(numKeys); // ["0", "1", "2", "3", "4"]

// Nested
var nested = { x: { y: 1 } };
for (var k in nested) { console.log(k); } // "x"
```

### Vereficacion

```js
var obj = { a: 1, b: 2, c: 3 };
var keys = [];
for (var k in obj) { keys.push(k); }
console.log(keys); // ["a", "b", "c"]

var arr = [10, 20, 30];
var indices = [];
for (var idx in arr) { indices.push(idx); }
console.log(indices); // ["0", "1", "2"]

var numKeys = [];
for (var n in 12345) { numKeys.push(n); }
console.log(numKeys); // ["0", "1", "2", "3", "4"]

var nested = { x: { y: 1 } };
for (var k in nested) { console.log(k); } // "x"
```

### Comparar salida raw (sin interpretar ANSI)

```bash
./zig-out/bin/lou run js/main.js 2>&1 | od -c
node js/main.js 2>&1 | od -c
```

### pendiente

- [x] Lexer: diferenciar `in` operator vs `for...in`
- [x] Parser: nodo `ForInLoop`
- [x] AST: `ForInLoop`
- [x] Evaluador: soporte `ForInLoop`
- [x] VM: compilar/interpretar `ForInLoop`
- [x] Verificación con `od -c` vs Node.js

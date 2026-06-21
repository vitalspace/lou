# Computed Property Keys in Object Literals

## status
implementado

## Problema
`tests/compat/computed-properties.lou` falla. Output actual:
```
undefined
undefined
undefined
```
(programa termina prematuramente con output incorrecto)

Output esperado (JS):
```
{ name: 'Alice' }
{ helloWorld: 42 }
{ '42': 'x' }
{ x: 1, y: 2, z: 3 }
{ literal: 'L', dyn: 99, also: 'A' }
{ fetchData: 'value' }
```

## Contexto
ES2015 permite computed property keys en object literals:
```js
const key = "name";
const obj = { [key]: "Alice" };  // { name: "Alice" }

{ ["hello" + "World"]: 42 }       // { helloWorld: 42 }

{ [42]: "x" }                     // { "42": "x" }

{ [a]: 1, [b]: 2, [c]: 3 }        // múltiples computed keys
```

Lou ya tiene unit tests pasando para computed properties (ver `src/evaluator.zig` líneas ~4730-4830). Pero el VM bytecode compiler no emite código correcto para `[expr]: val` en object literals, por lo que el path bytecode (que es el que usa el compat test) falla.

## Código que falla
```js
const key = "name";
const obj = { [key]: "Alice" };
console.log(obj);
```

Output: `undefined` o se imprime `{  }` (sin la propiedad).

## Implementacion sugerida
1. En VM bytecode compiler, cuando se compila un `ObjectLiteral` con properties que tienen `key_expr` (computed key):
   - Evaluar el object.
   - Para cada property: evaluar el key_expr (si está), luego el value.
   - Usar `set_prop` con la key string-ificada.
2. Alternativamente, delegar al AST evaluator via `eval_node`.

## Tests
- Unit tests existentes pasan (verificados).
- `tests/compat/computed-properties.lou` debe pasar.

## Verificación
```bash
./zig-out/bin/lou run tests/compat/computed-properties.lou
diff <(./zig-out/bin/lou run tests/compat/computed-properties.lou) \
     <(node tests/compat/computed-properties.js)
```

## pendiente
- ~~Implementar computed property keys en VM bytecode compiler.~~

## Solución
Dos partes: el lado de escritura y el lado de lectura.

### VM (`src/vm.zig`)
- `expr` para `ObjectLiteral` sólo usaba `prop.key` (estático); ahora
  detecta `key_expr` (computed) y defiere al AST evaluator via
  `eval_node` cuando algún property es computed.
- `get_prop` para `js_object` sólo aceptaba `string` keys (integer/float
  → `InvalidIndex`); ahora coerce a string (`indexToKey`-style) antes
  de buscar en el HashMap.

### Evaluator (`src/evaluator.zig`)
- `ObjectLiteral` handler usaba siempre `prop.key`; ahora evalúa
  `key_expr` si está presente y usa el resultado coerced a string via
  `indexToKey` (helper ya existente, reutilizado).

### Limitaciones
- En el `get_prop` para `js_object`, las keys allocadas dinámicamente
  para integer/float se freean inmediatamente con `defer` (en vez de
  añadirse a `env.owned_strings`). Funciona para el caso del test, pero
  técnicamente un leak: si la key se almacenara en otro lado (no es el
  caso aquí), se perdería. Aceptable porque `get_prop` no propaga la
  key — sólo la usa para el lookup.

### Resultados
- `tests/compat/computed-properties.lou` → PASS.
- 11/27 compat tests PASS (sin regresiones).

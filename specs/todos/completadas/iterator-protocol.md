# Iterator protocol (`Symbol.iterator`)

## status

**completada** — implementada (compat: 82 PASS / 3 FAIL / 1 SKIP)

`tests/compat/iterator-protocol.lou` ahora produce salida byte-idéntica a Node.

## Problema

`for...of` sólo aceptaba arrays, strings, generators e `ArrayIterator`.
Un objeto con `[Symbol.iterator]()` que devuelve `{ next() }` se recorría
cero veces, y `it.next()` sobre esos iteradores abortaba el proceso.

## Contexto

- Las claves símbolo se manglan a `@@<descripción>` (`ast.symbolPropertyName`).
  `Symbol.iterator` se guarda como `@@iterator`.
- Hay dos motores que deben coincidir: el evaluator y el VM (`get_iterator`,
  `iterator_next`).
- Los métodos en object literals se parseaban como propiedades normales, no
  como funciones, así que `{ next() { ... } }` no generaba una closure.

## Implementación

### `src/parser.zig`

- Nuevo `parseMethodProperty`: detecta `key(...) { ... }` en object literals
  (claves simples y computadas) y construye un `FunctionDeclaration` sin
  nombre con parámetros, defaults y `rest_param`.

### `src/evaluator.zig`

- Object literals: las claves computadas aceptan valores `symbol` y usan
  `symbolPropertyName` (registrando el string en `owned_strings`).
- `DirectCall` sobre un `.iterator` hace passthrough (permite
  `arr[Symbol.iterator]()`).
- `for...of` sobre `.js_object`: si existe `@@iterator`, invoca el método con
  `this` ligado al objeto, y en cada iteración llama a `next()` con `this`
  igual al iterador, leyendo `done`/`value`.
- Return anidado: un `return` dentro de un `BlockStatement` ahora marca
  `return_hit` en el entorno que lo contiene, así que aborta la función y no
  sólo el bloque.
- `src/environment.zig`: al copiar un scope no-heap, se retienen los
  ancestros heap-owned (se marcan `captured` y se registran en
  `closure_envs`); sin esto el scope de la función se liberaba al volver y la
  cadena de padres del closure quedaba colgando.
- `Environment.deinit` drena `iter_envs`/`closure_envs` antes de liberar las
  listas propias, y tolera un `outer` ya liberado (`deinited`) para no
  escribir en listas destruidas al cerrar el programa.

### `src/vm.zig`

- `get_iterator` con prong `.js_object`: busca `@@iterator`, lo invoca y
  pushea el iterador resultante.
- `iterator_next` con prong `.js_object`: si el objeto tiene `next`, lo llama
  y pushea `value`/`done` del resultado.
- Claves corregidas de `@@Symbol.iterator` a `@@iterator`.

## Verificación

- `diff <(./zig-out/bin/lou run tests/compat/iterator-protocol.lou) <(node tests/compat/iterator-protocol.js)`
- `bash tests/compat/run.sh` — 82 PASS / 3 FAIL / 1 SKIP
- `zig test src/evaluator.zig` y `zig test src/main.zig` — 1,068 tests

## pendiente

- [x] métodos shorthand en object literals
- [x] claves computadas con símbolos
- [x] `arr[Symbol.iterator]()`
- [x] `for...of` sobre iterables custom (evaluator y VM)
- [x] `next()` con estado capturado
- [x] return dentro de bloques anidados
- [x] tests compat y unitarios

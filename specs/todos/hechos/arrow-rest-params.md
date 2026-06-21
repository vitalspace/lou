# Arrow Function Syntax (`(...xs) => expr`)

## status
hecho

## Problema
`tests/compat/arrow-syntax.lou` fallaba. El último caso (rest parameters en arrow) no se ejecutaba:
```js
const head = (...xs) => xs[0];
console.log(head(1, 2, 3));  // expected: 1
```

Output actual antes del fix:
```
25
3.14
5
120
[ 2, 4, 6 ]
[ 2, 3 ]
```
(El programa terminaba sin imprimir `1`)

Error cuando se llamaba a la arrow con rest params:
```
error: UndefinedVariable
/src/evaluator.zig:394:17 in evaluate
```

## Implementación

### 1. AST (`src/ast.zig`)
Añadido `rest_param: ?[]const u8 = null` al struct `ArrowFunction`.

### 2. Parser (`src/parser.zig`)
- `parseArrowFunction()`: detecta `...nombre` como último parámetro y lo almacena en `rest_param`.
- `parsePrecedece()`: añadida detección de arrow function con un solo identificador sin paréntesis (`x => expr`), que faltaba en el baseline.

### 3. Evaluator (`src/evaluator.zig`)
En `invokeFunctionNode()` para `ArrowFunction`:
- Después de bindear los parámetros posicionales, si `rest_param != null`, crea un `ArrayObject` con los argumentos restantes (`args[func.parameters.len..]`) y lo asigna al nombre del rest en `func_env`.
- El array se registra en `env.arrays` para cleanup correcto.

### 4. VM (`src/vm.zig`)
En `callFuncNode()`:
- El switch de extracción de campos incluye `rest_param` para `ArrowFunction`.
- Tanto en el path de bytecode compilado como en el fallback al AST evaluator, si `rest_param` está set, crea el array y lo asigna antes de ejecutar el body.

## Verificación

```bash
$ ./zig-out/bin/lou run tests/compat/arrow-syntax.lou
25
3.14
5
120
[ 2, 4, 6 ]
[ 2, 3 ]
1

$ diff <(./zig-out/bin/lou run tests/compat/arrow-syntax.lou) \
       <(node tests/compat/arrow-syntax.js)
(empty)
```

Tests unitarios añadidos en `src/evaluator.zig`:
- `arrow function with rest param - single argument`
- `arrow function with rest param - empty rest`
- `arrow function with rest param - captures all arguments`
- `arrow function with leading params and rest param`

Todos los 842 tests unitarios pasan.

## Edge cases encontrados

1. **Compatibilidad con callbacks de builtins (`Array.prototype.map`)**: builtins como `map.zig` bindean los primeros N parámetros posicionales (`element`, `index`, `array`) pero no manejan `rest_param` del callback. `arr.map((x, ...rest) => rest.length)` no funciona aún — fuera del scope de este spec.

2. **Rest vacío**: `(...args) => args` con cero argumentos produce un `ArrayObject` con `elements.items.len == 0`. Correcto.

3. **Parámetros leading + rest**: `(a, b, ...rest) => rest` funciona — los primeros 2 args van a `a` y `b`, el resto al array.

## pendiente
- [x] Implementar rest parameters en arrow functions.

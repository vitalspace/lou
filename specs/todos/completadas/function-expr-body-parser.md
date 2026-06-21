# Function declaration: expression body consume comas en contextos de lista

## status

IMPLEMENTED

## Resumen

- **Fix**: `parseFunctionDeclaration` en `src/parser.zig:1265` ahora usa `parseExpressionBody` (en vez de `parseStatement`) para el body cuando no hay `{`. La helper `parseExpressionBody` (introducida por `arrow-function-edge-cases.md`) NO consume comas trailing, así que cada elemento de un array literal, cada argumento de llamada, cada rama de un ternario, etc. se parsea como una unidad independiente.
- **Block bodies** no afectados (`parseBlockStatement` consume hasta el `}` balanceado).
- **Tests**: 3 nuevos unit tests en `src/parser.zig` (function expression body en array, function con binary body en array, function en ternary). `tests/compat/function-expr-body.lou` Lou-specific (no se puede hacer compat test porque Node no acepta `function f() expr` syntax). Total: 862 → 865 unit tests pasando.

## Problema

`parseFunctionDeclaration` en `src/parser.zig:1265` usa `parseStatement` para el body cuando no hay `{`. `parseStatement` llama a `parseCommaExpression`, que consume comas greedy. Esto es el mismo bug que tenía `parseArrowFunction` antes del spec `arrow-function-edge-cases.md`, y rompe la separación de elementos en arrays, argumentos de llamada, etc.

```js
const arr = [function f() 1, function g() 2];
//            ^^^^^^^^^^^^^^^^ body consume hasta la siguiente ','
//                              ^^^^^^^^^^^^^^^^ debería ser elemento 2
console.log(arr.length);  // 1 (debería: 2)
console.log(arr[0]());    // [function] (body = (1, function g() 2))
```

Versión con block body funciona correctamente:

```js
const arr = [function f() { return 1; }, function g() { return 2; }];
console.log(arr.length);  // 2 ✓
console.log(arr[0]());    // 1 ✓
```

Versión con paréntesis también funciona (los parens aíslan la expresión):

```js
const arr = [(function f() 1), (function g() 2)];
console.log(arr.length);  // 2 ✓
```

## Código que falla

```js
// Array literal
const arr = [function f() 1, function g() 2];
console.log(arr.length);  // error: 1 (debería: 2)

// Argumentos de llamada
console.log([function f() 1, function g() 2]);
// imprime: [ [function] ]   (debería: [ [function], [function] ])

// Ternario con function en cada rama
const x = 5;
const sign = x > 0
    ? function() "pos"
    : function() "neg";
// consequent consume la rama alternate como parte del body
```

```
error: longitud incorrecta
/home/vital/Desktop/lou/src/parser.zig:1265
```

## Implementacion sugerida

### Fix: usar `parseExpressionBody` en `parseFunctionDeclaration`

Aplicar el mismo fix que en `arrow-function-edge-cases.md`: cambiar el body parser de `parseStatement` a `parseExpressionBody` cuando no hay block body. `parseExpressionBody` no consume comas, así que cada elemento del array se parsea como una unidad independiente.

```zig
// src/parser.zig:1265
const body = if (this.current_token.type == .LBrace)
    try this.parseBlockStatement()
else
    try this.parseExpressionBody();
```

`parseExpressionBody` ya existe (introducido en el spec de arrow functions) y es exactamente la helper correcta: parsea una expresión sin consumir comas trailing.

### Verificación adicional

Buscar otros call-sites que usen `parseStatement` para un body que NO debería consumir comas:

- `parseArrowFunction` — ya arreglado
- `parseFunctionDeclaration` — este spec
- `parseGeneratorDeclaration` (mismo path que FunctionDeclaration) — verificar
- `parseYieldExpression` — body opcional, ya usa `parseExpression` que NO consume comas

### Plan

1. Cambiar el body parser en `parseFunctionDeclaration` a `parseExpressionBody`.
2. Verificar que el spec `arrow-function-edge-cases.md` sigue pasando (no debería romperse).
3. Añadir tests para:
   - `function f() expr` en array literal con múltiples elementos
   - `function f() expr` como argumentos de llamada
   - `function f() expr` en consequent/alternate de ternario
4. Verificar que no se rompe ningún test existente.

## Archivos de referencia

- `src/parser.zig:1265` — `parseFunctionDeclaration` body parser
- `src/parser.zig:83-85` — `parseExpressionBody` (helper introducido por arrow-function-edge-cases)
- `completadas/arrow-function-edge-cases.md` — el mismo bug ya resuelto para arrow functions
- `completadas/arrow-function-syntax.md` — implementación base
- ECMAScript 14.1.2 — `FunctionExpression`
- ECMAScript 14.1.4 — `FunctionBody` (puede ser `FunctionBody : ExpressionBody` en algunas specs)

### JS Examples Complejos

```js
// Function expression body en array (Lou-specific, JS lo rechaza)
const ops = [
    function add(a, b) a + b,
    function sub(a, b) a - b,
    function mul(a, b) a * b
];
console.log(ops.length);        // 3
console.log(ops[0](2, 3));      // 5
console.log(ops[1](5, 2));      // 3
console.log(ops[2](4, 5));      // 20

// Function expression body como argumentos
console.log([1, 2, 3].map(function(x) x * x));
// [ 1, 4, 9 ]

// Function expression body en ternary
const classify = n => n > 0
    ? function() "positive"
    : function() "negative";
console.log(classify(5)());    // "positive"
console.log(classify(-5)());   // "negative"

// Mixto con block bodies
const handlers = [
    function() { return 1; },
    function() 2,
    function() { return 3; }
];
console.log(handlers.length);  // 3
console.log(handlers[0]());    // 1
console.log(handlers[1]());    // 2
console.log(handlers[2]());    // 3
```

### Vereficacion

```bash
./zig-out/bin/lou run tests/compat/function-expr-body.js
node tests/compat/function-expr-body.js
```

Diff esperado: longitudes de arrays correctas, valores retornados correctos, exit 0 en ambos.

### Comparar salida raw (sin interpretar ANSI)

```bash
./zig-out/bin/lou run tests/compat/function-expr-body.js 2>&1 | od -c
node tests/compat/function-expr-body.js 2>&1 | od -c
```

### pendiente

- [x] Reproducir el bug: `function f() expr` en array context
- [x] Cambiar body parser en `parseFunctionDeclaration` a `parseExpressionBody`
- [x] Tests: array con function expression bodies, argumentos, ternario
- [x] Verificar que `tests/compat/arrow-edge-cases.lou` y `arrow-syntax.lou` siguen pasando
- [x] Verificar que no se rompe ningún test existente (862 → 865 unit tests)

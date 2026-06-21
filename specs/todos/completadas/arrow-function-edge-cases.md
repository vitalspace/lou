# Arrow functions: casos límite y follow-ups

## status

IMPLEMENTED

## Resumen

- **Bug 1 (ternario)**: el check de arrow function se movió de `parseExpression` a `parsePrecedece` (con guard `precedence == .lowest`). `parseExpression` ahora es un wrapper de `parsePrecedece(.lowest)`. Esto cubre consequent/alternate del ternario y cualquier otra llamada recursiva a `.lowest`.
- **Bug 2 (consistencia en body)**: `parseArrowFunction` y el path de empty-arrow en `parseCallArguments` ahora usan `parseExpressionBody` en vez de `parseStatement`, evitando que se consuman comas greedy en contextos de lista (arrays, args, etc.).
- **Tests**: nuevo `tests/compat/arrow-edge-cases.{js,lou}` y 5 nuevos unit tests en `src/parser.zig` (ternario con arrow, ternario anidado, arrow en `return`, arrow en array literal, arrow en RHS de asignación). Total: 858 → 863 tests pasando.

## Problema

Durante la implementación de `arrow-function-syntax.md` se detectaron varios bugs adicionales que no se cubren en otros specs pendientes. Estos afectan la paridad de las arrow functions con JavaScript moderno.

## Bugs cubiertos por otros specs

Estos NO se reescriben aquí; ver los specs correspondientes:

- Captura léxica (`(x) => (y) => x + y`) → `pendientes/closure-over-let.md`
- Object methods (`{ f: x => x*2 }.f()`) → `pendientes/object-method-call.md`
- Rest en `function` declaration (`function f(...xs) {}`) → `pendientes/rest-parameters.md`

## Bugs nuevos cubiertos por este spec

### 1. Arrow en consequent/alternate del ternario

Una arrow function unparenthesized no se reconoce como consequent o alternate del operador ternario (`? :`). El parser espera `:` después del consequent, pero encuentra `=>` y lanza `error: ExpectedColon`.

```js
const x = 5;
const sign = x > 0 ? x => "pos" : x => "neg";
//                                  ^ error: ExpectedColon
```

Forma parenthesized funciona porque `parsePrimary` para `LParen` ya maneja arrow functions vía `parseArrowFunction`. Pero la forma `x => expr` depende del check en `parseExpression`, que no se ejecuta cuando `parsePrecedece(.lowest)` se invoca directamente desde el path del ternario.

```
error: ExpectedColon
/home/vital/Desktop/lou/src/parser.zig:362:17
```

La versión parenthesized sí funciona:

```js
const sign = x > 0 ? (n) => "pos" : (n) => "neg";
console.log(sign(1));   // "pos"
console.log(sign(-1));  // "neg"
```

### 2. `parseArrowFunction` existente usa `parseStatement` para el body

`parseArrowFunction` en `src/parser.zig:1317` (path de `(x) => expr` en `parsePrimary`) usa `parseStatement` para el body cuando no hay `{`. `parseStatement` llama a `parseCommaExpression`, que consume comas greedy. Está enmascarado en la mayoría de contextos (call args, ternario, paréntesis) pero causa bugs sutiles:

```js
// Hipotético, no verificado
const arr = [(a) => a, (b) => b];  // puede o no funcionar dependiendo del caller
```

El fix reciente para `parseExpression` (en el spec de syntax) usa `parseExpressionBody` que NO consume comas. Por consistencia, `parseArrowFunction` debería usar la misma helper.

### 3. Forma mixta: arrow con block body dentro de un comma context

El fix del spec de syntax usa `parseBlockStatement` para el block body, lo cual está bien (consume hasta `}` balanceado, no consume comas). Pero no se ha probado con block bodies en arrow functions dentro de arrays u otros comma-separated contexts.

## Código que falla

### Bug 1: ternario

```js
const x = 5;
const sign = x > 0 ? x => "pos" : x => "neg";
console.log(sign(1));   // error: ExpectedColon (debería: "pos")
```

### Bug 2: `parseArrowFunction` con body expression en comma context

El bug es difícil de reproducir sin preparar el contexto exacto. Una forma de exponerlo es un arrow function con body que incluye un binary expression dentro de un array literal:

```js
const fns = [(x) => x + 1, (x) => x + 2];
// Funciona porque parseCallArguments maneja comas, pero internamente
// el body puede haber consumido tokens de más.
```

(Verificar exactamente qué tokens se consumen. Si funciona en el test actual, este bug es latente pero debería corregirse por consistencia.)

## Implementacion sugerida

### Fix bug 1: arrow en ternario

Mover la detección de `x => expr` de `parseExpression` a `parsePrecedece` cuando `precedence == .lowest`. Esto cubre:
- El caso top-level (que ya funciona).
- El consequent y alternate del ternario (que actualmente falla).
- Cualquier otra llamada recursiva a `parsePrecedece(.lowest)`.

```zig
fn parsePrecedece(this: *Parser, precedence: ast.Precedence) !*ast.Node {
    var left = try this.parsePrimary();

    while (...) { /* binary operator loop */ }

    // Arrow function: x => expr. Only at lowest precedence so we don't
    // hijack sub-expressions like `a + b => ...`.
    if (precedence == .lowest and
        this.current_token.type == .Arrow and
        left.* == .Identifier)
    {
        const param_name = left.Identifier.name;
        this.nextToken(); // consume '=>'
        const body_node = if (this.current_token.type == .LBrace)
            try this.parseBlockStatement()
        else
            try this.parseExpressionBody();
        const params_slice = try this.allocator.alloc([]const u8, 1);
        params_slice[0] = param_name;
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ArrowFunction = .{
            .parameters = params_slice,
            .rest_param = null,
            .body = body_node,
        } };
        return node;
    }

    // Ternary
    if (@intFromEnum(precedence) <= @intFromEnum(ast.Precedence.Assign) and this.current_token.type == .Question) {
        ...
    }

    return left;
}
```

Y `parseExpression` se simplifica:

```zig
pub fn parseExpression(this: *Parser) anyerror!*ast.Node {
    return try this.parsePrecedece(.lowest);
}
```

### Fix bug 2: consistencia en `parseArrowFunction`

Cambiar el body parsing en `parseArrowFunction` (línea ~1317) de `parseStatement` a `parseExpressionBody`:

```zig
const body = if (this.current_token.type == .LBrace)
    try this.parseBlockStatement()
else
    try this.parseExpressionBody();
```

### Plan

1. Mover el arrow check a `parsePrecedece` (y simplificar `parseExpression`).
2. Actualizar `parseArrowFunction` para usar `parseExpressionBody`.
3. Añadir tests para:
   - Ternario con arrow en ambas ramas
   - Arrow en `for` init/condition/update (e.g. `for (let i = 0; fn(i) < 10; i++)`)
   - Arrow en argumentos de `return` (`return x => x + 1`)
4. Verificar que el spec `arrow-function-syntax.md` sigue pasando.

## Archivos de referencia

- `src/parser.zig:48-78` — `parseExpression` (donde está el arrow check actual)
- `src/parser.zig:322-380` — `parsePrecedece` (ternario parsing)
- `src/parser.zig:1317` — `parseArrowFunction` (path LParen, usa `parseStatement`)
- `completadas/arrow-function-syntax.md` — implementación base
- `pendientes/closure-over-let.md` — closure capture
- `pendientes/object-method-call.md` — object method calls
- `pendientes/rest-parameters.md` — rest en function declaration
- ECMAScript 13.2 — Arrow Function Definitions
- ECMAScript 13.3 — Method Definitions
- ECMAScript 14.7 — Conditional Operator `? :`

### JS Examples Complejos

```js
// Bug 1: ternario con arrow en ramas
const x = 5;
const sign = x > 0
    ? n => "positive"
    : n => "negative";
console.log(sign(10));   // "positive"
console.log(sign(-10));  // "negative"

// Ternario anidado con arrows
const classify = n =>
    n === 0   ? z => "zero"
    : n > 0   ? p => "positive"
    :          m => "negative";
console.log(classify(5)(1));    // "positive"
console.log(classify(-5)(-1));  // "negative"

// Arrow en argumentos de llamada complejos
const ops = {
    add:      (a, b) => a + b,
    sub:      (a, b) => a - b,
    apply:    (f, x) => f(x)
};
console.log(ops.apply(x => x * 2, 5));  // 10

// Arrow en array literal con block bodies
const handlers = [
    x => { return x + 1; },
    x => { return x * 2; }
];
console.log(handlers[0](5));  // 6
console.log(handlers[1](5));  // 10
```

### Vereficacion

```bash
./zig-out/bin/lou run tests/compat/arrow-edge-cases.js
node tests/compat/arrow-edge-cases.js
```

Diff esperado: ninguna línea difiere, exit 0 en ambos.

### Comparar salida raw (sin interpretar ANSI)

```bash
./zig-out/bin/lou run tests/compat/arrow-edge-cases.js 2>&1 | od -c
node tests/compat/arrow-edge-cases.js 2>&1 | od -c
```

### Implementación

- [x] Reproducir bug 1: ternario con arrow en consequent/alternate
- [x] Mover arrow check de `parseExpression` a `parsePrecedece(.lowest)`
- [x] Simplificar `parseExpression` a wrapper de `parsePrecedece(.lowest)`
- [x] Cambiar `parseArrowFunction` body parser a `parseExpressionBody`
- [x] Cambiar empty-arrow en `parseCallArguments` a `parseExpressionBody` (consistencia)
- [x] Tests: ternario con arrow, ternario anidado, arrow en `return`, arrow en array literal
- [x] Verificar que `tests/compat/arrow-syntax.lou` sigue pasando
- [x] Verificar que no se rompe ningún test existente (858 → 863 unit tests)

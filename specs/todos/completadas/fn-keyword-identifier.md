# `fn` como keyword colisiona con identifier en expression position

## status

IMPLEMENTED

## Resumen

- **Opción A aplicada**: eliminado `fn` del keyword map en `src/lexer.zig`. `function` queda como la única keyword para function declarations/expressions, alineando con JS (donde `fn` no es keyword).
- **Tests actualizados**:
  - `test "keywords"` en `lexer.zig` ya no espera `.Fn` para `fn`.
  - `test "function declaration"` usa `function` en vez de `fn`.
  - `test "evaluate function declaration and call"` en `evaluator.zig` usa `function` en vez de `fn`.
  - 1 nuevo unit test: `test "fn is identifier, not keyword"` verifica que `let fn = 5` tokeniza como `let` `Identifier("fn")` ...
- **Compat test**: `tests/compat/fn-as-identifier.{js,lou}` cubre `let fn = 5`, `(fn) => fn * 2`, `o["fn"]()`, `[1,2,3].map(fn => fn * 2)`, etc. La salida matchea Node exactamente. Total: 870 → 871 unit tests pasando.

## Problema

`fn` se tokeniza como keyword `.Fn` (junto con `function`) en el lexer (`src/lexer.zig:439-440`) y `parsePrimary` siempre trata `.Fn` como `parseFunctionDeclaration`. Esto hace que `fn` sea **reservado en toda posición**, incluyendo expression position donde en JavaScript sería un identifier válido (porque `fn` no es palabra reservada de JS — solo `function` lo es).

```js
// No compila — el parser intenta parsear como FunctionDeclaration
let fn = "hello";                      // error: ExpectedLParen
const cb = fn => fn * 2;               // error: ExpectedLParen (o similar)
console.log(fn);                       // error: ExpectedLParen

// Afecta arrow function como callback
function takesCallback(fn) { return fn(42); }
console.log(takesCallback(x => x * 2)); // error: ExpectedIdentifier
// (parser ve `fn` después de `(`, cree que es FunctionDeclaration)
```

Mismo problema con `function` (ya reservado en JS, así que el comportamiento es "consistente" con JS — pero `fn` es una extensión de Lou, no de JS).

## Contexto

JS reserva `function` como FutureReservedWord en strict mode y como keyword en sloppy mode. Pero `fn` no existe en JS — es una extensión de Lou. Si Lou quiere tener `fn` como alias de `function`, debería tener el mismo tratamiento contextual que las palabras reservadas tienen en otros lenguajes:

- **Statement position** (inicio de statement): `fn () { ... }` → function declaration/expression.
- **Expression position** (después de un operador, dentro de un paréntesis, etc.): `fn` debería ser un identifier normal.

Actualmente el lexer no distingue contexto, así que `.Fn` siempre activa `parseFunctionDeclaration`.

## Código que falla

```js
// Variable con nombre `fn`
let fn = 42;
console.log(fn);

// Arrow function con parámetro `fn`
const f = (fn) => fn + 1;
console.log(f(10));        // 11

// Objeto con propiedad `fn`
const o = { fn: () => 1 };
console.log(o.fn());       // 1

// Como callback
const arr = [1, 2, 3].map(fn => fn * 2);
console.log(arr);          // [ 2, 4, 6 ]

// Como nombre de función en expression position
const g = function fn() { return 42; };
console.log(g());          // 42 (JS acepta named function expression)

// Como nombre de variable en destructuring
const { fn, x } = { fn: 1, x: 2 };
console.log(fn, x);        // 1 2

// Destructuring array
const [fn, x] = [10, 20];
console.log(fn, x);        // 10 20
```

Todos estos fallan con `error: ExpectedLParen` o `error: ExpectedIdentifier`.

## Implementacion sugerida

### Opción A: separar `fn` y `function` en dos keywords

En el lexer:

```zig
// src/lexer.zig:439-440
.{ "fn", .Fn },
.{ "function", .Fn },
```

Convertir a:

```zig
.{ "function", .Fn },
// `fn` ya no es keyword — siempre es Identifier
```

Esto hace que `fn` sea siempre un identifier. En statement position, `fn () { ... }` se parsearía como `parseExpression` que vería `fn` (Identifier) seguido de `(` (FunctionCall) y luego `{` (Block) — eso NO es lo que queremos. Pero `function () { ... }` seguiría siendo la forma canónica de declarar funciones.

**Problema**: `fn name() { ... }` deja de funcionar como shorthand. Habría que promover `function` y dejar de usar `fn`.

### Opción B: hacer `fn` contextual en el parser

Mantener `fn` como keyword pero solo en statement position. Para esto:

1. El lexer sigue produciendo `.Fn` para `fn`.
2. El parser, en lugar de tratar `.Fn` como function declaration en `parsePrimary`, **delega** a `parseStatement` que ya tiene el caso correcto.
3. `parseStatement` (línea 96) ya maneja `.Fn` como `parseFunctionDeclaration` cuando aparece al inicio de un statement.
4. `parsePrimary` (línea 409) debería **eliminar** el caso `.Fn` y dejarlo como `error.UnexpectedToken`. Si por alguna razón `fn` aparece en expression position, debería ser un identifier (no keyword).

Pero esto rompe `fn` en expression position (donde queremos que sea identifier). El lexer debería producir `.Identifier` cuando `fn` aparece en expression position. Pero el lexer no tiene contexto.

**Alternativa C: Tokenizar `fn` como Identifier cuando no es seguido de `(` o `(name`**

El lexer podría mirar el siguiente carácter:
- Si `fn` está seguido de whitespace + `(` o whitespace + identifier + `(`, producir `.Fn`.
- Si no, producir `.Identifier` con literal `"fn"`.

Esto es contextual y frágil (e.g. `fn[0]` sería identifier, pero `fn()` sería keyword).

### Opción D (recomendada): no hacer nada — es una decisión de diseño

`fn` siendo reservado en toda posición es **consistente con JS** (que reserva `function` igual). Si Lou quiere ser compatible con JS al 100%, no debería usar `fn` como identifier.

El "fix" apropiado es **documentar la limitación** y promover `function` como la forma canónica.

**Pero**: la documentación actual de Lou probablemente dice que `fn` es un alias. Si la decisión de diseño es mantener `fn` como alias, entonces hay que aceptar que `fn` no es un identifier válido.

### Decisión recomendada: Opción A

Promover `function` como keyword única para function declarations/expressions, y dejar `fn` como identifier normal. Esto:

1. Es compatible con JS.
2. Permite `fn` como identifier.
3. Hace que `function` sea la única forma de declarar funciones (más explícita).

**Cambios necesarios**:

1. En `src/lexer.zig:439-440`, eliminar `.{ "fn", .Fn },` (mantener `.{ "function", .Fn },`).
2. Actualizar docs/README para reflejar que `function` es la forma canónica.
3. Tests existentes que usan `fn` como keyword fallarán — actualizar a `function`.

### Plan

1. Decidir entre Opción A (promover `function`, eliminar `fn` como keyword) u Opción B (mantener `fn` keyword pero hacerlo contextual).
2. Si Opción A: eliminar la entrada del lexer, actualizar tests/docs.
3. Si Opción B: refactorizar `parsePrimary` para no manejar `.Fn` directamente.
4. Tests: `let fn = 1`, `(fn) => fn * 2`, `[1,2,3].map(fn => fn * 2)`, etc.

## Archivos de referencia

- `src/lexer.zig:439-440` — `getKeywordType`, donde `fn` y `function` mapean a `.Fn`
- `src/parser.zig:409-411` — `parsePrimary` caso `.Fn` (siempre `parseFunctionDeclaration`)
- `src/parser.zig:198-199` — `parseStatement` caso `.Fn` (también `parseFunctionDeclaration`)
- `src/evaluator.zig` — `FunctionDeclaration` y `ArrowFunction`
- ECMAScript 12.2 — Keywords and Reserved Words
- ECMAScript 13.2 — Arrow Function (usa identifiers, no keywords)

### JS Examples Complejos

```js
// Variable con nombre `fn`
let fn = 42;
const inc = x => x + fn;
console.log(inc(8));           // 50

// Objeto con propiedad `fn`
const o = { fn: 100, x: 1 };
const { fn, x } = o;
console.log(fn + x);           // 101

// Array con función nombrada
const arr = [(fn => fn * 2), (fn => fn + 1)];
console.log(arr[0](5));        // 10
console.log(arr[1](5));        // 6

// Como nombre de función en expression
const f = function fn() { return fn; };
console.log(typeof f);         // "function"
console.log(f.name);           // "fn" (JS lo permite)

// En set/get
const obj = {
    _x: 0,
    get fn() { return this._x; },
    set fn(v) { this._x = v; }
};
obj.fn = 42;
console.log(obj.fn);          // 42

// Como callback
const filter = [1, 2, 3, 4].filter(fn => fn > 2);
console.log(filter);          // [ 3, 4 ]
```

### Vereficacion

```bash
./zig-out/bin/lou run tests/compat/fn-as-identifier.js
node tests/compat/fn-as-identifier.js
```

Diff esperado: ningún error `ExpectedLParen` o `ExpectedIdentifier`, todos los ejemplos compilan y producen la salida esperada, exit 0 en ambos.

### Comparar salida raw (sin interpretar ANSI)

```bash
./zig-out/bin/lou run tests/compat/fn-as-identifier.js 2>&1 | od -c
node tests/compat/fn-as-identifier.js 2>&1 | od -c
```

### pendiente

- [x] Decidir entre Opción A (eliminar `fn` keyword) u Opción B (contextual)
- [x] Eliminar `fn` del keyword map en `src/lexer.zig`
- [x] Actualizar tests que usaban `fn` como keyword (lexer + evaluator)
- [x] Tests: `let fn = 1`, `(fn) => fn * 2`, `arr.map(fn => fn)`, `function fn() {}`
- [x] Verificar que `function () { ... }` sigue funcionando como declaración
- [x] Verificar que no se rompe ningún test existente (870 → 871 unit tests)

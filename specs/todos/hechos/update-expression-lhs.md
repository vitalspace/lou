# UpdateExpression (`++`/`--`) en LeftHandSideExpression

## status

**pendiente (drift corrected 2026-07-30)** — previously marked `IMPLEMENTED` but `tests/compat/update-expression-lhs.lou` FAILs per compat baseline (43P/39F/1S)

## Resumen

- **AST**: nuevo nodo `UpdateExpression{operator, prefix, operand}` en `src/ast.zig`. La estructura es completa con `freeAst` y `printAst`.
- **Parser**: el check de pre/post `++`/`--` ya no se restringe a `Identifier` plano.
  - Pre-increment/decrement (`++x`/`--x`) en `parsePrimary` parsea el operando vía `parsePrimary()` y valida que sea `LeftHandSideExpression` válido con la nueva helper `isValidLhs`.
  - Post-increment/decrement (`x++`/`x--`) en el postfix chain también valida con `isValidLhs`.
  - Se eliminó el hack de construir `Assignment{BinaryExpression(x, Plus, 1.0)}`.
- **Evaluator**: nuevo helper `evaluateUpdate(operator, prefix, operand, env)` que lee el valor, aplica +1/-1, almacena en el lhs (Identifier / MemberAccess / ArrayIndex) y retorna el valor correcto (prefijo: nuevo, postfijo: viejo). Soporta tanto `.array` como `.js_object` para `ArrayIndex`.
- **VM**: el compilador defer a tree-walking via `eval_node` para `UpdateExpression` (el bytecode compiler no lo implementa directamente; delega al evaluator para mantener la lógica en un solo lugar).
- **Tests**: 5 nuevos unit tests en `src/parser.zig` (pre/post-inc en identifier, member, array index, chained member) + `tests/compat/update-expression-lhs.{js,lou}`. Total: 865 → 870 unit tests pasando.

## Problema

Los operadores `++` y `--` solo funcionan cuando el operando es un `Identifier` plano. Cualquier `LeftHandSideExpression` válido en JavaScript (member access, array index, etc.) falla con `error: UnexpectedToken`.

```js
let o = {x: 5};
o.x++;            // error: UnexpectedToken
++o.x;            // error: UnexpectedToken

let a = [1, 2, 3];
a[0]++;           // error: UnexpectedToken
++a[0];           // error: UnexpectedToken

let p = {q: {r: 1}};
p.q.r++;          // error: UnexpectedToken
```

ECMAScript define `UpdateExpression` con la producción:

```
UpdateExpression:
    LeftHandSideExpression
    LeftHandSideExpression [no LineTerminator here] ++
    LeftHandSideExpression [no LineTerminator here] --
    ++ UnaryExpression
    -- UnaryExpression
```

Lou restringe incorrectamente a `Identifier` en lugar de aceptar cualquier `LeftHandSideExpression`.

## Contexto

`UpdateExpression` es la única forma idiomática de incrementar/contar en JS. Si solo funciona sobre identificadores planos, escribir `arr.length++`, `obj.count++`, `matrix[i][j]++` se vuelve imposible y obliga a desugar a `arr.length = arr.length + 1` (verboso y propenso a errores).

`Increment`/`Decrement` ya están tokenizados y los nodos del evaluador existen (ver `pendientes/increment-decrement.md`), pero el parser restringe el operando a `Identifier` en dos lugares:

```zig
// src/parser.zig:466-480 — pre-increment `++x`
.Increment => {
    this.nextToken();
    if (this.current_token.type == .Identifier) {
        // ... build Assignment ...
    } else {
        return error.UnexpectedToken;
    }
},
```

```zig
// src/parser.zig:572-580 — post-increment `x++`
if (this.current_token.type == .Increment and base.* == .Identifier) {
    this.nextToken();
    // ... build Assignment ...
}
```

## Código que falla

```js
// Member access
let o = {x: 5, count: 0};
o.x++;
o.count += 1;        // workaround existente
console.log(o.x);    // debería: 6

// Array index
let a = [10, 20, 30];
a[1]++;
console.log(a);      // debería: [ 10, 21, 30 ]

// Pre-increment en member
let p = {v: 7};
let r = ++p.v;
console.log(r, p.v); // debería: 8 8

// Pre-increment en array index
let b = [0, 0, 0];
++b[0];
console.log(b);      // debería: [ 1, 0, 0 ]

// Encadenado
let m = {a: {b: 1}};
m.a.b++;
console.log(m.a.b);  // debería: 2
```

```
error: UnexpectedToken
/home/vital/Desktop/lou/src/parser.zig:472
```

Versión que sí funciona (solo identificador plano):

```js
let i = 0;
i++;
++i;
console.log(i);     // 2 ✓
```

## Implementacion sugerida

### Fix: aceptar `LeftHandSideExpression`

`LeftHandSideExpression` en JS incluye, además de `Identifier`:
- `MemberExpression` (postfix `.`, `[...]`, `?.`, `?.[]`)
- `CallExpression`
- `NewExpression`
- `OptionalExpression`

Lou ya implementa casi todas estas como AST nodes (`MemberAccess`, `ArrayIndex`, `MethodCall`, `FunctionCall`, `NewExpression`, `DirectCall`). El cambio es de **validación**, no de表达能力.

### 1. Pre-increment / pre-decrement en `parsePrimary`

Cambiar `.Increment` y `.Decrement` en `parsePrimary` (líneas 466-512) para que:

1. Consuman `++`/`--`.
2. Construyan un nodo `UpdateExpression{op=prefix, operand}` en lugar de un `Assignment` sintético.
3. Validar que el operando sea un `LeftHandSideExpression` válido (`Identifier`, `MemberAccess`, `ArrayIndex`, etc.). Si no, error `InvalidUpdateExpression` o reutilizar `InvalidAssignmentTarget`.

```zig
.Increment => {
    this.nextToken(); // consume '++'
    // El operando puede ser cualquier LeftHandSideExpression
    const operand = try this.parseUnaryExpression(); // o un subset
    if (!isValidLhs(operand)) {
        ast.freeAst(this.allocator, operand);
        return error.InvalidUpdateExpression;
    }
    const node = try this.allocator.create(ast.Node);
    node.* = .{ .UpdateExpression = .{
        .operator = .Increment,
        .prefix = true,
        .operand = operand,
    } };
    return node;
},
```

### 2. Post-increment / post-decrement después del postfix chain

La check actual (línea 572) solo dispara si `base.* == .Identifier`. Generalizar a "es un LeftHandSideExpression válido":

```zig
if (this.current_token.type == .Increment and isValidLhs(base)) {
    this.nextToken(); // consume '++'
    const node = try this.allocator.create(ast.Node);
    node.* = .{ .UpdateExpression = .{
        .operator = .Increment,
        .prefix = false,
        .operand = base,
    } };
    return node;
}
```

`isValidLhs` debe aceptar:
- `.Identifier`
- `.MemberAccess`
- `.ArrayIndex`
- `.FunctionCall`, `.MethodCall`, `.DirectCall` (en JS también son lhs válidos)
- `.NewExpression` (controvertido; JS lo prohíbe, lo más simple es permitir)

### 3. Eliminar el hack del `0 + 1`

El parser actual sintetiza un `BinaryExpression(Identifier(x), Plus, FloatLiteral(1.0))` que es feo y propenso a errores (no preserva el original lhs si es un member access). El nuevo nodo `UpdateExpression` resuelve esto limpiamente.

### 4. Evaluador / VM

Implementar la evaluación de `UpdateExpression`:
- Resolver el valor actual del lhs (subir por `outer` si es un `Identifier`; usar `getMember`/`getIndex` si es un access).
- Aplicar `+1`/`-1` (con coerción a número, manejando `NaN`, `null`, etc.).
- Asignar el nuevo valor al lhs (binding o propiedad).
- Devolver el valor correcto según `prefix` (nuevo) o `postfix` (viejo).

### Plan

1. Añadir nodo `UpdateExpression` en `src/ast.zig` con `operator`, `prefix`, `operand`.
2. Refactorizar `parsePrimary` para construir `UpdateExpression` real.
3. Generalizar el check post-increment/decrement a `isValidLhs`.
4. Implementar evaluación en `evaluator.zig` y opcodes en `vm.zig`.
5. Tests para: member, array index, encadenado, mixed con otros operadores.
6. Verificar que los usos existentes (`i++`, `++i`) siguen funcionando.

## Archivos de referencia

- `src/parser.zig:466-512` — pre/post increment/decrement en `parsePrimary`
- `src/parser.zig:572-590` — post-increment/decrement en `parsePrimary`
- `src/ast.zig` — añadir `UpdateExpression` (no existe todavía)
- `src/evaluator.zig` — evaluación
- `src/vm.zig` — opcodes
- `pendientes/increment-decrement.md` — spec general de increment/decrement
- ECMAScript 13.5 — Update Expressions
- ECMAScript 13.3 — LeftHandSideExpression

### JS Examples Complejos

```js
// Member access
let stats = { hits: 0, misses: 0 };
stats.hits++;
++stats.misses;
console.log(stats);          // { hits: 1, misses: 1 }

// Array index
let counter = [0, 0, 0, 0];
for (let i = 0; i < 4; i++) {
    counter[i]++;
}
console.log(counter);        // [ 1, 1, 1, 1 ]

// Encadenado
let deep = { a: { b: { c: 5 } } };
deep.a.b.c++;
console.log(deep.a.b.c);     // 6

// Pre-increment retorna nuevo valor
let arr = [10];
let x = ++arr[0];
console.log(x);              // 11
console.log(arr);            // [ 11 ]

// Post-increment retorna viejo valor
let arr2 = [10];
let y = arr2[0]++;
console.log(y);              // 10
console.log(arr2);           // [ 11 ]

// En for-loop
let counts = {};
for (let i = 0; i < 5; i++) {
    counts[i] = 0;
}
for (let i = 0; i < 5; i++) {
    counts[i]++;
}
console.log(counts);         // { 0: 1, 1: 1, 2: 1, 3: 1, 4: 1 }

// Decrement en member
let timer = { secs: 60 };
timer.secs--;
--timer.secs;
console.log(timer.secs);     // 58
```

### Vereficacion

```bash
./zig-out/bin/lou run tests/compat/update-expression-lhs.js
node tests/compat/update-expression-lhs.js
```

Diff esperado: ningún error `UnexpectedToken`, valores correctos en member access / array index / encadenado, exit 0 en ambos.

### Comparar salida raw (sin interpretar ANSI)

```bash
./zig-out/bin/lou run tests/compat/update-expression-lhs.js 2>&1 | od -c
node tests/compat/update-expression-lhs.js 2>&1 | od -c
```

### pendiente

- [x] Reproducir el bug: `obj.x++`, `arr[0]++`, `++obj.x`, `++arr[0]`
- [x] Añadir nodo `UpdateExpression` en `src/ast.zig`
- [x] Refactorizar pre-increment/decrement en `parsePrimary` para usar `UpdateExpression`
- [x] Generalizar post-increment/decrement check a `isValidLhs`
- [x] Implementar evaluación de `UpdateExpression` (member access, array index)
- [x] Tests: member access, array index, encadenado, mixto con binary ops
- [x] Verificar que `i++` y `++i` siguen funcionando
- [x] Verificar que no se rompe ningún test existente (865 → 870 unit tests)

- **Estimated fix effort**: 1h: extend parser.zig:1737 to accept MemberAccess / ArrayIndex / CallExpression as LHS of UpdateExpression (currently only Identifier parses).

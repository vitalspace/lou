# Operadores lógicos && y || deben retornar operandos

## status

IMPLEMENTADO

## Problema

Los operadores `&&` y `||` siempre retornan un booleano. En ECMAScript, retornan el valor del operando que determina el resultado. Esto es fundamental para patrones como `var x = value || "default"`.

## Contexto

ECMAScript define:
- `a || b`: retorna `a` si `a` es truthy, sino `b`
- `a && b`: retorna `a` si `a` es falsy, sino `b`

## Baseline (qué existe ya)
- `src/vm.zig:1098` — opcode `.and_`: `self.push(.{ .boolean = truthy(a) and truthy(b) });` — **bug raíz: push boolean, no operando**
- `src/vm.zig:1099` — opcode `.or_`: mismo bug
- `src/evaluator.zig:601-636` — branch And/Or en evaluator: retorna `.boolean` — **mismo bug en fallback AST path**
- `src/vm.zig:1100` — opcode `.nullish`: `self.push(if (a == .null or a == .void) b else a);` — **patrón correcto: retorna operando**
- `src/vm.zig:1638` — `truthy` helper (boolean/integer/float/string/void/null/hole)
- `src/evaluator.zig:603-610` — `left_truthy` local (evalúa truthiness por tipo)
- `src/builtins/boolean/boolean.zig:61` — `truthy` para `.big_int` (`!big.value.eqlZero()`)
- `src/parser.zig:1733` — unit test verifica que `.And` parsea
- `src/lexer.zig:224,232` — tokens `.And`/`.Or` mapeados a `&&`/`||`

## Quick verify (estado actual)
```bash
# Reproduce bug: retorna boolean en vez de operando
./zig-out/bin/lou run -e 'console.log("hello" || "world")' 2>&1
./zig-out/bin/lou run -e 'console.log(0 && 42)' 2>&1
./zig-out/bin/lou run -e 'var n = 0; console.log(n || "fallback")' 2>&1
# Referencia: `??` ya funciona
./zig-out/bin/lou run -e 'console.log(null ?? "x")' 2>&1
```

## Patrones a seguir
- `src/vm.zig:1100` — `nullish`: usa `if (a == .null or a == .void) b else a` — replicar este shape para `and_` (con `truthy(a)` como predicado: si truthy→a, sino→b) y `or_` (si truthy→b, sino→a — ¡OJO: el orden en stack es invertido!)
- `src/evaluator.zig:601-636` — branch And/Or: reemplazar el `return .{ .boolean = ... }` por `return if (truthy) left else right;` (los nodos ya están evaluados a `ast.Value`)
- `src/builtins/boolean/boolean.zig:61` — para soportar BigInt en `truthy`: `if (a == .big_int) { /* eqlZero check */ }`

## Gotchas
- El operador `??` (vm.zig:1100) ya funciona y retorna operandos — NO debe romperse al modificar `.and_`/`.or_`
- Stack order: VM pop'a en orden inverso al push; `b` se pop'a primero, después `a`. En la lógica `a || b`, el operando izquierdo (`a`) está en el top del stack cuando se pusheó
- Short-circuit: `&&` no evalúa `b` si `a` es falsy; `||` no evalúa `b` si `a` es truthy — preservar (afecta side-effects en operandos)
- Retorno debe preservar el tipo exacto (BigInt, string, number, boolean, object) — no coerce
- `truthy` no existe como helper público; en el VM se usa la función local `truthy` (vm.zig:1638), en el evaluator hay una local `left_truthy` (evaluator.zig:603)
- Ambos paths (VM bytecode y AST evaluator) deben modificarse — el compiler emite `.and_`/`.or_` para casos simples y delega a `eval_node` para el resto

## Código que falla

```js
var name = user.name || "Anonymous";   // Debería: "Anonymous" si name es ""
                                         // Actual: true (boolean)
var count = obj.count && obj.count.val; // Debería: 0 si count es 0
                                         // Actual: false (boolean)

console.log("hello" || "world");  // Debería: "hello", Actual: true
console.log(0 && 42);            // Debería: 0,      Actual: false
console.log("" || "fallback");   // Debería: "fallback", Actual: true
console.log("truthy" && "yes");  // Debería: "yes",  Actual: true
```

## Implementacion sugerida

En `evaluator.zig:601-636` y `vm.zig:1074-1075`:

```zig
// || operator
.Or => {
    const a = self.pop();
    const b = self.pop(); // note: operands may be reversed due to stack order
    if (truthy(a)) {
        self.push(a);  // return truthy operand, not true
    } else {
        self.push(b);  // return right operand
    }
},

// && operator
.And => {
    const a = self.pop();
    const b = self.pop();
    if (!truthy(a)) {
        self.push(a);  // return falsy operand, not false
    } else {
        self.push(b);  // return right operand
    },
},
```

El operador `??` ya funciona correctamente (retorna operandos).

## Tests

Añadir un test de compatibilidad en `tests/compat/`. El runner (`tests/compat/run.sh`) compara el output de Lou contra el de Node y solo marca PASS si ambos exit code y stdout normalizado son idénticos.

### Convención de archivos

- `tests/compat/<nombre>.js` — referencia canónica. Debe ejecutarse con `node` y producir el output esperado.
- `tests/compat/<nombre>.lou` — el mismo programa escrito para Lou. Debe producir output idéntico a la versión `.js`.
- Si el spec cubre sintaxis **específica de Lou** (no existente en JS, e.g. `function f() expr` como expression body, `..` range, `match`), omitir el `.js` y dejar solo el `.lou` — el runner marcará SKIP automáticamente.

### Verificación local

```bash
# 1. Lou produce el output esperado
./zig-out/bin/lou run tests/compat/<nombre>.lou

# 2. Node produce el output esperado (si hay .js)
node tests/compat/<nombre>.js

# 3. Diff (debe ser vacío)
diff <(./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1) \
     <(node tests/compat/<nombre>.js 2>&1)

# 4. Correr toda la suite
bash tests/compat/run.sh
```

### Tests unitarios (parser/lexer/evaluator)

Además del compat test, añadir tests unitarios en el archivo `.zig` correspondiente (`src/parser.zig`, `src/lexer.zig`, `src/evaluator.zig`, etc.) que verifiquen la estructura del AST o el comportamiento del lexer/evaluator para casos individuales. Los unit tests son útiles para casos donde el compat test sería demasiado grande o donde queremos verificar la forma exacta del AST.

## Archivos de referencia

- `src/evaluator.zig:601-636` — evaluación de And/Or
- `src/vm.zig:1074-1075` — opcodes And/Or
- ECMAScript 13.13 Binary Logical Operators

### JS Examples Complejos

```js
// Default value pattern
var config = userConfig || {};
var port = process.env.PORT || 3000;
var name = obj.name || "Unknown";

// Guard pattern
var first = arr.length && arr[0];
var val = obj && obj.nested && obj.nested.value;

// Short-circuit evaluation
console.log(false && "never");  // false
console.log(true || "never");   // true
console.log(0 || "" || "found"); // "found"
console.log(1 && "hello" && "world"); // "world"
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-logical-operands.js
node js/test-logical-operands.js
```

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente
- [x] VM opcodes `.and_`/`.or_` retornan operandos (no booleanos)
- [x] Compiler short-circuit para `.And`/`.Or` deja el operando correcto en el stack
- [x] Evaluator `BinaryExpression.And`/`.Or` retorna `left` (operando) en vez de `.boolean`

## Resolución (2026-06-29)

Verificado: la implementación ya estaba completa en el código actual.

- **VM** (`src/vm.zig:1315-1316`): `.and_` → `self.push(if (truthy(a)) b else a)`, `.or_` → `self.push(if (truthy(a)) a else b)` — retornan operandos correctamente.
- **Compiler** (`src/vm.zig` `expr()/.And` y `.Or`): usa short-circuit con `jump_if_false`/`jump_if_true` que deja el operando en el stack, no un booleano.
- **Evaluator** (`src/evaluator.zig` `BinaryExpression.And`/`.Or`): retorna `left` o `try evaluate(b.right, env)` — preserva el tipo del operando.

Output verificado con Node.js (diff vacío):
```
console.log("hello" || "world")   → hello      ✓
console.log(0 && 42)               → 0          ✓
console.log("" || "fallback")      → fallback   ✓
console.log("truthy" && "yes")     → yes        ✓
console.log(false && "never")      → false      ✓
console.log(true || "never")       → true       ✓
console.log(0 || "" || "found")    → found      ✓
console.log(1 && "hello" && "world") → world    ✓
```

## Edge cases encontrados durante implementación

Listar aquí los bugs, comportamientos inesperados o requisitos descubiertos
mientras se implementaba este spec. Cada edge case debe ser promovido a su
propio spec (usando esta misma plantilla) si requiere cambios de diseño
propios, o documentado inline si es un fix puntual.

Ejemplos de edge cases típicos:
- Comportamiento cuando se mezcla el tipo con primitivos incompatibles
  (TypeError vs coerción silenciosa).
- Formato de impresión / `toString` — sufijo, base, mayúsculas.
- Comparación loose vs strict.
- Conversión a otros tipos (string concat, Number, BigInt).
- División por cero, exponente negativo, overflow.
- Capturabilidad del error por `try/catch` JS (no abortar el proceso).

Plantilla para promover un edge case a spec:
1. Crear `specs/todos/pendientes/<spec>-edge-<caso>.md` siguiendo esta plantilla.
2. Enlazar desde este spec principal con un enlace relativo.
3. Verificar que el test correspondiente cubre el caso.


## Estado del test (auto 2026-06-29)

- Compat test match: `logical-operators-operand-return.lou` (EXACT)
- Test status: `PASS`

- Diff: empty (Lou output and Node output identical for all 8 cases).


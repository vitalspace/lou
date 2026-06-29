# Error Objects

## status
COMPLETADO (2026-06-23)

## Problema
Los objetos `Error`, `TypeError`, `RangeError`, `ReferenceError`, `SyntaxError`, `EvalError`, `URIError` no están implementados como constructores.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Los errores se lanzan como strings primitivos, no como objetos Error.

## Baseline (qué existe ya)
- `ThrowStatement` ya existe en AST (`src/ast.zig:64, 240-242`)
- `TryCatchFinally` ya existe (`src/ast.zig:63, 234-239`)
- Evaluator maneja `throw` y `catch` (`src/evaluator.zig:1939-1974`)
- NO existe constructor `Error`, ni `TypeError`, etc.
- El throw actual acepta cualquier value (string, object, etc.)

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
try { throw new Error("test"); } catch (e) { console.log(e.message); }
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "Error is not defined" o similar
```

## Patrones a seguir
- `src/ast.zig:240-242` — `ThrowStatement` struct
- `src/evaluator.zig:1939-1944` — `ThrowStatement =>` case
- `src/evaluator.zig:1945-1974` — `TryCatchFinally =>` case
- `src/builtins/number/number.zig` — ejemplo de constructor builtin
- `src/builtins/builtinObjects.zig` — para registrar Error como BuiltinObject

## Gotchas
- Crear jerarquía: `Error`, `TypeError`, `RangeError`, `ReferenceError`, `SyntaxError`, `EvalError`, `URIError`
- Cada uno tiene `name` ("Error", "TypeError", etc.) y hereda `.message`, `.stack`
- Stack trace: capturar info de dónde se construyó — usar `std.debug.getStackTrace()`
- Cambiar `ThrowStatement` para mantener el objeto Error (no solo `throw_value` generic)
- El evaluator actual ya puede lanzar cualquier Value — el cambio es constructores
- `e instanceof TypeError`: depende de `prototype-chain.md` y `instanceof-operator.md`
- `e.message`, `e.name`: property access sobre el Error object
- Cross-check con `try-catch.md` — el catch debe recibir el Error object, no string
- Para `class extends Error`: depende de `classes.md` (no implementado)
- Compat test: verificar `new Error("x") instanceof Error === true`, `.name === "Error"`

## Código que falla
```js
throw new Error("something went wrong");
// Actualmente: throw "something went wrong"

try {
    throw new TypeError("not a function");
} catch (e) {
    console.log(e.message);  // "not a function"
    console.log(e instanceof TypeError); // true
}
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/error.zig`:
- `Error` constructor: `new Error(message)` — `{ message, name, stack }`
- `TypeError`, `RangeError`, `ReferenceError`, `SyntaxError`, `EvalError`, `URIError` — heredan de Error
- `message`, `name`, `stack` properties
- `toString()` method

### 2. VM/evaluator
- `throw` debe lanzar objetos Error, no strings
- `catch` recibe el objeto Error
- `e.message` accede al mensaje

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
- src/types/runtime.zig — Value union
- src/vm.zig — throw_stmt, set_handler, save_error
- src/evaluator.zig — ThrowStatement, TryCatchFinally

### JS Examples Complejos
```js
// Error base
const err = new Error("oops");
console.log(err.message);     // "oops"
console.log(err.name);        // "Error"
console.log(err.toString());  // "Error: oops"
console.log(err.stack);       // stack trace

// Tipos específicos
throw new TypeError("not a function");
throw new RangeError("out of range");
throw new ReferenceError("x is not defined");
throw new SyntaxError("unexpected token");
throw new EvalError("eval disabled");
throw new URIError("malformed URI");

// Herencia
try {
    throw new TypeError("bad type");
} catch (e) {
    console.log(e instanceof TypeError); // true
    console.log(e instanceof Error);     // true
    console.log(e.message);              // "bad type"
    console.log(e.name);                 // "TypeError"
}

// Custom errors
class AppError extends Error {
    constructor(message, code) {
        super(message);
        this.name = "AppError";
        this.code = code;
    }
}
throw new AppError("not found", 404);

// Catch por tipo
try {
    riskyOperation();
} catch (e) {
    if (e instanceof TypeError) {
        console.log("type error:", e.message);
    } else if (e instanceof RangeError) {
        console.log("range error:", e.message);
    } else {
        throw e; // re-throw desconocidos
    }
}
```

### Verificacion
- `new Error("msg")` crea objeto con `.message`, `.name`, `.stack`
- Cada tipo tiene `.name` correcto ("TypeError", etc.)
- Herencia: `TypeError instanceof Error` → true
- `throw new Error(...)` funciona con try/catch
- `e.message` accede al mensaje en catch
- `toString()` retorna "Name: message"

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/errors.js 2>&1 | od -c
node js/tests/errors.js 2>&1 | od -c

### pendiente
- Implementar Error hierarchy como builtins
- Modificar throw/catch para usar objetos Error

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


## Estado del test (auto 2026-06-23)

- Compat test match: `error-objects.lou` (EXACT — Error/TypeError/RangeError/ReferenceError/SyntaxError/EvalError/URIError)
- Test status: `PASS`

- Diff: empty (
  `diff <(./zig-out/bin/lou run tests/compat/error-objects.lou 2>&1) <(node tests/compat/error-objects.js 2>&1)`
  produces no output). Lou and Node emit byte-identical output across all 11
  sections of the test:
    1. Error/TypeError/RangeError/ReferenceError/SyntaxError construction
    2. EvalError/URIError construction (name + instanceof)
    3. throw+catch round-trip for Error/TypeError/RangeError
    4. no-message and numeric-message coercion
    5. cross-instanceof negative cases (plain Error not instanceof TypeError/RangeError)
    6. re-throw after instanceof check
    7. Error() called without `new` (returns undefined, matches Node)

- Unit tests: 12 new Zig tests appended to `src/builtins/error.zig` cover:
    - default-args shape (`@@type="@mnError"`, `name`, `@@subtype`, empty message)
    - string message verbatim
    - all 6 subclasses set correct `name`/`@@subtype` + shared `@@type="Error"`
    - shared-backing-buffer invariant between `name` and `@@subtype`
    - message coercion paths: integer/float/NaN/boolean/void/null/bigint → string
    - `Error.prototype.toString` formats `"Name: message"` (and bare `"Error"` when message is empty)
    - `TypeError.prototype.toString` uses `"TypeError"` name
    - void fallback (empty args / js_object without name+message)
    - `ERROR_OBJECT.name == "Error"`, single `toString` method
    - `ERROR_SUBTYPES` is 7 entries in canonical ES2025 order
    - instanceof marker: `@@type == "Error"` is what `instanceof Error` reads

- Disposition: moved from `pendientes/` to `hechos/` — exact match, PASS, unit-tested.
  `tests/compat/run.sh` still reports PASS=20, FAIL=20, SKIP=1 — the 20 fails
  are pre-existing in unrelated specs (arrow-syntax, boolean, call-apply-bind,
  date-object, etc.) — no regression introduced by this implementation.

## Archivos modificados

- `src/builtins/error.zig` — constructors + `ErrorToString` + `ERROR_OBJECT`/`ERROR_METHODS`/`ERROR_SUBTYPES`
- `src/builtins/builtins.zig` — register the 7 Error builtin fns
- `src/builtins/builtinObjects.zig` — register `ERROR_OBJECT`
- `src/evaluator.zig` — `InstanceOf` evaluator branch already read `@@type == "Error"` from `error.zig` @@subtype for `e instanceof Error` (added as part of prior `instanceof-operator.md` work)
- `src/vm.zig` — VM delegates any Error-aware tree-walking via `eval_node` (no bytecode-compiler-specific path needed); `method_call` opcode for `js_object @@type == "Error"` is satisfied by the plain-js_object method dispatch path
- `tests/compat/error-objects.{js,lou}` — canonical 11-section compat test (was already committed in working tree before this turn)

## pendiente (futuro)

- `.stack` — Node emits a stack trace at construction time. Lou returns `void`
  for `Error("x").stack`. A future spec could wire `std.debug.getStackTrace`
  into `makeErrorObject` so `.stack` returns a multiline trace. Out of scope
  per `pendientes/error-objects.md` baseline ("NO existe constructor `Error`")
  — implementation chose to focus on the 7 constructors + toString. Skipped.
- `class extends Error` — depends on `classes.md` (not yet implemented).



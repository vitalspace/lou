# Logical Assignment Operators (&&=, ||=, ??=)

## status

**pendiente (drift corrected 2026-07-30)** — `tests/compat/logical-assignment.lou` FAILs per compat baseline (43P/39F/1S)

## Problema
Los operadores de asignación lógica (`&&=`, `||=`, `??=`) no están implementados.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. ES2021 agregó estos operadores que combinan lógica y asignación.

## Baseline (qué existe ya)
- Lexer tiene `.Nullish` (`??`) en TokenType (`src/lexer.zig:51`)
- Lexer tiene `.And` (`.And`) y `.Or` (`.Or`) para `&&` y `||`
- Compound assignments ya existen: `+=`, `-=`, `*=`, `/=`, `%=` (`src/lexer.zig:20-25`)
- Parser tiene `parseAssignment` para compound assigns (`src/parser.zig:770-830`)
- Evaluator despacha compound assigns en `Assignment =>` o similar
- Faltan los 3 tokens: `.AndAssign` (`&&=`), `.OrAssign` (`||=`), `.NullishAssign` (`??=`)

## Quick verify (estado actual)
```bash
echo 'let a = 0; a ||= 5; console.log(a);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (||= no se reconoce)
```

## Patrones a seguir
- `src/lexer.zig:175-195` — handler de `&` y `|` como ejemplo para construir `&&`, `&&=`, `||`, `||=`
- `src/lexer.zig:269-280` — handler de `?` para `??`, base para `??=`
- `src/parser.zig:770-830` — `parseAssignment` para agregar las 3 ramas nuevas
- `src/evaluator.zig` — buscar `Assignment =>` o compound assign dispatch
- `src/evaluator.zig:380-450` — caso `BinaryExpression` para `.And`/`.Or`/`.Nullish` como template de short-circuit

## Gotchas
- SEMÁNTICA crítica:
  - `a &&= b` → `a && (a = b)` — evalúa RHS solo si a es truthy
  - `a ||= b` → `a || (a = b)` — evalúa RHS solo si a es falsy
  - `a ??= b` → `a ?? (a = b)` — evalúa RHS solo si a es null/undefined
- SHORT-CIRCUIT es la clave — no es simplemente "compute then assign". RHS no se evalúa si no es necesario
- Cross-check con `null-undefined-equality.md` — `??=` usa el mismo concepto
- Solo funciona con identificadores y member access (no arbitrary expressions en LHS en ES2021 strict, pero permisivo en sloppy)
- Para member access (`obj.prop ??= value`), usar `setInScope`-style lookup

## Código que falla
```js
let a = 0;
a ||= 5;
console.log(a); // 5

let b = null;
b ??= 10;
console.log(b); // 10

let c = 1;
c &&= 2;
console.log(c); // 2
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar tokens: `AndAssign` (`&&=`), `OrAssign` (`||=`), `NullishAssign` (`??=`)

### 2. Parser (src/parser.zig)
- En `parseAssignment()`, detectar `&&=`, `||=`, `??=`
- `a &&= b` equivale a `a && (a = b)` (short-circuit)
- `a ||= b` equivale a `a || (a = b)`
- `a ??= b` equivale a `a ?? (a = b)`

### 3. VM (src/vm.zig)
- Opcode `and_assign`, `or_assign`, `nullish_assign`
- Short-circuit: solo evaluar RHS si es necesario

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
- src/lexer.zig — tokens de operadores
- src/parser.zig — parseAssignment()
- src/vm.zig — Op enum

### JS Examples Complejos
```js
// ||= — asigna si es falsy
let config = {};
config.timeout ||= 3000;
console.log(config.timeout); // 3000

let existing = "hello";
existing ||= "default";
console.log(existing); // "hello" (no se sobreescribe)

// ??= — asigna si es null/undefined
let options = { verbose: false };
options.debug ??= true;
console.log(options.debug); // true (verbose es false, no null)

options.verbose ??= true;
console.log(options.verbose); // false (ya tiene valor)

// &&= — asigna si es truthy
let obj = { count: 5 };
obj.count &&= obj.count * 2;
console.log(obj.count); // 10

let nil = null;
nil &&= 42;
console.log(nil); // null (no asigna porque nil es falsy)

// Con objetos
const settings = { theme: "dark" };
settings.fontSize ??= 16;
settings.theme ??= "light";
console.log(settings.fontSize); // 16
console.log(settings.theme);    // "dark"

// Array patterns
const arr = [1, 2, 3];
arr.length &&= 0; // si tiene elementos, vaciar
console.log(arr); // []
```

### Verificacion
- `&&=` solo asigna si el valor actual es truthy
- `||=` solo asigna si el valor actual es falsy
- `??=` solo asigna si el valor actual es null/undefined
- Short-circuit: RHS no se evalúa si no es necesario
- Funciona con propiedades de objetos

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/logical-assign.js 2>&1 | od -c
node js/tests/logical-assign.js 2>&1 | od -c

### pendiente
- Implementar tokens, parser, y VM opcodes para &&=, ||=, ??=

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


## Estado del test (auto 2026-06-22)

- Compat test match: `bigint-logical-edge.lou` (FUZZY — logical)
- Test status: `PASS`

- Disposition: test PASSES — but stays in pendientes/ because match is FUZZY on tokens; verify spec scope matches the test (manual confirmation required before move).


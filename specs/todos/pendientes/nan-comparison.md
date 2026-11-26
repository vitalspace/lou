# NaN en comparaciones <= >=

## status

**pendiente** — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SKIP)

`tests/compat/nan-comparison.lou` sigue FAIL. Primera divergencia (línea 1), Lou vs Node:

```text
Lou : true
Node: false
```

`NaN <= 5` se compila como `!(NaN > 5)` = `!(false)` = `true`. `<=` y `>=` necesitan el caso NaN explícito (cualquier comparación con NaN es `false`).

```bash
diff <(./zig-out/bin/lou run tests/compat/nan-comparison.lou) <(node tests/compat/nan-comparison.js)
```

## Problema

`NaN <= 5` retorna `true` en el VM. Esto ocurre porque `LessThanOrEqual` se implementa como `!(a > b)`. Dado que `NaN > 5` es `false`, `!false` es `true`, lo cual es incorrecto. ECMAScript requiere que cualquier comparación con NaN retorne `false`.

## Contexto

ECMAScript 13.10 Relational Operators: todas las comparaciones con NaN retornan `false`:
- `NaN < x` → false
- `NaN > x` → false
- `NaN <= x` → false
- `NaN >= x` → false

## Baseline (qué existe ya)
- `LessThanOrEqual` se compila como `!(a > b)` (`src/vm.zig:789-790` o similar)
- `NaN` existe como valor f64 (NaN en Zig es `std.math.nan(f64)` o `std.mem.bytesAsValue(f64, ...)`)
- `valGt` (o similar) existe en VM; retorna false cuando alguno es NaN — el bug está en el corto-circuito del `<=`

## Quick verify (estado actual)
```bash
echo 'console.log(NaN <= 5, NaN >= 5);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "true true" — debería ser "false false"
```

## Patrones a seguir
- `src/vm.zig:786-790` — switch sobre `.LessThan`, `.LessThanOrEqual`, `.GreaterThan`, `.GreaterThanOrEqual`
- `src/evaluator.zig` — buscar el caso `BinaryExpression =>` para operadores `LessThan`/`GreaterThan`
- Ambos archivos tienen la misma lógica que necesita el fix

## Gotchas
- Cambio simple per se pero requiere cambiar 2 lugares (evaluator + VM)
- Detectar NaN: en Zig, `value != value` es true solo para NaN
- NO usar `@isNaN(value)` con f64 — `std.math.isNan(value)` es lo correcto
- Cross-check con `equality-coercion.md`: `NaN == NaN` también debe ser false
- Aplicar a `<`, `>`, `<=`, `>=` — los 4 operadores relacionales
- Evaluar también `NaN <= NaN` → false (no `true` por casualidad)

## Código que falla

```js
console.log(NaN <= 5);    // Debería: false, Actual: true
console.log(NaN >= 5);    // Debería: false, Actual: true
console.log(NaN < 5);     // Debería: false, Actual: false (correcto)
console.log(NaN > 5);     // Debería: false, Actual: false (correcto)
```

## Implementacion sugerida

En `vm.zig:789-790`, implementar `<=` y `>=` directamente en vez de como negación del inverso:

```zig
// Antes:
.LessThanOrEqual => { const b = self.pop(); const a = self.pop(); try self.push(if (valGt(a, b)) Value.false else Value.true); },

// Después:
.LessThanOrEqual => {
    const b = self.pop();
    const a = self.pop();
    // NaN comparisons always false
    if (isNaN(a) or isNaN(b)) {
        try self.push(Value.false);
    } else {
        try self.push(if (valGt(a, b)) Value.false else Value.true);
    }
},

// Similar for GreaterThanOrEqual
```

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

- `src/vm.zig:789-790` — LessThanOrEqual/GreaterThanOrEqual opcodes
- ECMAScript 13.10 Relational Operators

### JS Examples Complejos

```js
// NaN is not comparable to anything
console.log(NaN == NaN);     // false
console.log(NaN === NaN);    // false
console.log(NaN <= NaN);     // false
console.log(NaN >= NaN);     // false
console.log(NaN < 0);        // false
console.log(NaN > 0);        // false
console.log(NaN <= Infinity); // false

// isNaN check pattern
function safeCompare(a, b) {
    if (isNaN(a) || isNaN(b)) return false;
    return a <= b;
}
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-nan-comparison.js
node js/test-nan-comparison.js
```

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente
- [ ] *(Pendiente: detallar los pasos concretos de implementación derivados de las secciones anteriores.)*

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

- Compat test match: `-` (NO-MATCH)
- Test status: `-`

- Disposition: stays in pendientes/ — no corresponding test exists in tests/compat/. Create tests/compat/nan-comparison.lou + tests/compat/nan-comparison.js to enable automatic PASS/FAIL tracking.


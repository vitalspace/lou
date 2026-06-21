# try/catch/finally: semántica correcta

## status

NOT IMPLEMENTED

## Problema

El `try/catch/finally` tiene múltiples bugs semánticos:
1. Errores en el bloque `catch` se tragan silenciosamente (`else |_| {}`)
2. El bloque `finally` no siempre ejecuta
3. `return` dentro de `try` no ejecuta `finally` antes de retornar

## Contexto

ECMAScript 14.15 The try statement: `finally` SIEMPRE ejecuta, incluso si hay `return`, `break`, o `throw`. Los errores en `catch` deben propagarse después de `finally`.

## Baseline (qué existe ya)
- AST ya tiene `TryCatchFinally` (`src/ast.zig:234-239`)
- Evaluator YA maneja try/catch/finally (`src/evaluator.zig:1945-1974`) — pero con bugs:
  - Línea 1967: `else |_| {}` traga errores del catch
  - Falta verificar que `finally` corre antes de propagar errores del catch
  - No considera el caso de `return` dentro de try
- Ver `try-catch.md` para el spec general

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
try {
    throw new Error("outer");
} catch (e) {
    throw new Error("inner");
}
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
echo "---"
node /tmp/t.lou 2>&1
# Actual: ambos terminan, pero Lou puede tragar el error
```

## Patrones a seguir
- `src/evaluator.zig:1945-1974` — case `TryCatchFinally` actual; modificar para fix
- `src/environment.zig:60-63` — `throw_hit` y `throw_value` para rastrear estado de throw
- `src/evaluator.zig` — buscar `return_hit` para entender el patrón de "early return with cleanup"
- ECMAScript 14.15 — especificación paso-por-paso

## Gotchas
- El `return` dentro de try+finally ejecuta finally ANTES de retornar
- Si finally hace throw, ese throw reemplaza al return original
- Si finally tiene un return, ese return reemplaza al del try
- Hay que distinguir entre "el bloque terminó normal" vs "throw/return/break"
- Cross-check con `try-catch.md` (spec general) y `error-objects.md`
- Cambio sutil pero crítico: en línea 1967 cambiar `else |_| {}` a `else |catch_err| { ... try finally ...; return catch_err; }`
- Si hay return en try, guardar el valor en env (`return_value`), ejecutar finally, luego retornar
- Compat test `tests/compat/try-finally-semantics.js` — varios casos: try+return+finally, try+throw+finally, catch+throw+finally

## Código que falla

```js
// Error swallowed in catch
try {
    throw new Error("outer");
} catch (e) {
    throw new Error("inner"); // Se traga silenciosamente
}

// Finally not running
try {
    throw 1;
} catch (e) {
    throw 2; // finally no ejecuta
} finally {
    console.log("finally"); // No se imprime
}

// return in try
function test() {
    try {
        return 1;
    } finally {
        console.log("finally"); // Debería ejecutar antes del return
    }
}
```

## Implementacion sugerida

En `evaluator.zig:1954-1967`:

```zig
// Fix 1: Catch errors must propagate after finally
if (evaluate(cb, env)) |v| {
    catch_val = v;
} else |catch_err| {
    // Run finally BEFORE propagating catch error
    if (fb) |finally_block| {
        _ = evaluate(finally_block, env) catch {};
    }
    return catch_err; // Propagate, don't swallow
}

// Fix 2: Finally must always run
// Ensure finally block executes in ALL paths:
// - try succeeds, no catch → finally
// - try throws, catch succeeds → finally
// - try throws, catch throws → finally, then propagate
// - return in try → finally, then return
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

- `src/evaluator.zig:1954-1967` — try/catch/finally evaluación
- `src/vm.zig:619-693` — VM try/finally compilation
- ECMAScript 14.15 The try statement

### JS Examples Complejos

```js
// Finally always runs
function test() {
    try {
        console.log("try");
        throw 1;
    } catch (e) {
        console.log("catch", e);
        throw 2;
    } finally {
        console.log("finally"); // Must print
    }
}
// Expected output: "try", "catch 1", "finally", then uncaught 2

// Return in try
function getValue() {
    try {
        return 42;
    } finally {
        console.log("cleanup"); // Must run before return
    }
}
console.log(getValue()); // "cleanup", then 42
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-try-catch-finally.js
node js/test-try-catch-finally.js
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

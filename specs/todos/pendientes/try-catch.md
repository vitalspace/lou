# try-catch

## status
pendiente

## Problema 
Implementar soporte para try-catch en el lenguaje JavaScript interpretado por Lou. Actualmente no existe soporte para manejo de excepciones.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Las excepciones no están implementadas en el lenguaje.

## Baseline (qué existe ya)
- Lexer YA tiene tokens `.Try`, `.Catch`, `.Finally`, `.Throw` (`src/lexer.zig:92-95`)
- AST YA tiene `TryCatchFinally` y `ThrowStatement` (`src/ast.zig:234-242`)
- Evaluator YA maneja try/catch/finally parcialmente (`src/evaluator.zig:1945-1974`)
- VM tiene compilación parcial (`src/vm.zig:619-693`)
- Environment tiene campos `throw_hit` y `throw_value` (`src/environment.zig:60-61`)
- FALTA: tests compat dedicados, semántica correcta de finally (ver `try-catch-finally-semantics.md`)

## Quick verify (estado actual)
```bash
echo 'try { throw "x"; } catch(e) { console.log(e); }' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: puede que funcione parcialmente, pero hay bugs en catch/finally
```

## Patrones a seguir
- `src/ast.zig:234-242` — `TryCatchFinally` y `ThrowStatement` structs (referencia para nuevo node)
- `src/evaluator.zig:1945-1974` — implementación actual; aquí hay bugs documentados (ver try-catch-finally-semantics)
- `src/environment.zig:60-63` — `throw_hit`/`throw_value` fields para propagación
- `src/parser.zig:1180-1188` — `parseTryStatement` (buscar línea exacta)

## Gotchas
- BUGS CONOCIDOS documentados en `try-catch-finally-semantics.md` — finally no siempre ejecuta, errors en catch se tragan
- Throw cross-function: el `throw` debe propagarse a través de funciones anidadas buscando el catch más cercano
- `throw expr` evalúa expr primero, luego propaga el valor
- Cross-check con `error-objects.md` — si `throw new Error()` debe capturar como Error vs string
- Compat test: crear `tests/compat/try-catch.js` y `.lou` con varios patrones (try/catch, try/finally, throw en catch)

## Código que falla
```js
try {
    throw "error";
} catch (e) {
    console.log(e);
}
```
Actualmente no parsea ni ejecuta try-catch.

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar keywords:
- `.Try` - palabra clave `try`
- `.Catch` - palabra clave `catch`

Actualizar `getKeywordType()` para incluirlos.

### 2. AST (src/ast.zig)
Agregar `NodeType`:
- `.TryStatement` - estructura con `{ block: *Node, handler: ?*Node }`
- `.CatchClause` - estructura con `{ param: ?[]const u8, body: *Node }`

Actualizar `printAst()` y `freeAst()` para soportar los nuevos tipos.

### 3. Parser (src/parser.zig)
- `parseTryStatement()` - parsear `try { block } catch (param) { block }`
- `parseCatchClause()` - parsear el bloque catch con parámetro opcional

### 4. VM/Compiler (src/vm.zig)
Agregar operación:
- `.try_` - intenta ejecutar bloque, captura excepción
- `.throw_` - lanza una excepción

Implementar máquina de excepciones con stack de handlers.

### 5. Evaluator (src/evaluator.zig)
Manejar excepciones en tiempo de ejecución:
- `evaluateTryStatement()` - ejecutar bloque try, si falla ejecutar handler
- `throw()` - lanzar error que busca el catch más cercano

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

### JS Examples Complejos 
```js
// try-catch básico
try {
    throw "error message";
} catch (e) {
    console.log("caught:", e);
}

// try-catch con múltiples throw
try {
    if (condition) throw "first";
    throw "second";
} catch (err) {
    console.log(err);
}

// try-finally (opcional)
try {
    doSomething();
} finally {
    cleanup();
}

// try-catch-finally (opcional)
try {
    throw "error";
} catch (e) {
    console.log(e);
} finally {
    console.log("cleanup");
}

// nested try-catch
try {
    try {
        throw "nested error";
    } catch (inner) {
        throw "outer error";
    }
} catch (e) {
    console.log("caught outer:", e);
}
```

### Vereficacion
- Parser debe reconocer `try` y `catch` como palabras clave
- AST debe generar nodos `TryStatement` y `CatchClause`
- Evaluator debe capturar errores y ejecutar el bloque catch
- Las variables del catch deben estar en scope dentro del bloque

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

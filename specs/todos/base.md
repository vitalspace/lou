# title

## status

pendiente

## Problema

## Contexto

## Baseline (qué existe ya)

- [Estado actual: tokens/AST nodes/opcodes/funciones que ya están implementados. Verificar con grep, no inventar file:line refs.]

## Quick verify (estado actual)

```bash
# Comando de una línea que reproduce el código que falla
[command]
# Actual: [error/salida esperada vs actual]
```

## Patrones a seguir

- `src/<file>:<line>` — [descripción breve del patrón similar ya implementado]

## Gotchas

- [Bullet list de cosas a tener en cuenta al implementar]

## Código que falla

## Implementacion sugerida

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

### Verificacion

```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou
node tests/compat/<nombre>.js
```

Diff esperado: ninguna línea difiere, exit 0 en ambos.

### Comparar salida raw (sin interpretar ANSI)

```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente

- [ ] Accionable checklist derivado de Implementación sugerida

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
1. Crear `specs/todos/pendientes/<spec>-edge-<caso>.md` siguiendo esta misma plantilla.
2. Enlazar desde este spec principal con un enlace relativo.
3. Verificar que el test correspondiente cubre el caso.

---

## Gotchas comunes (referencia rápida)

Si tu spec toca alguna de estas áreas, revisar esta lista:

### Añadir campo a `Environment` (`src/environment.zig`)
- Agregar el campo al struct (~line 37)
- Inicializar en `initWithIo` (~line 91)
- Inicializar en `initBlock` (~line 125)
- Promover o liberar en `deinit` (~line 253) — patrón: si tiene outer, append al outer; si no, liberar

### Añadir AST node (`src/ast.zig`)
- Definir el struct en `Node` union (~line 48)
- Actualizar `printAst` (~line 470)
- Actualizar `freeAst` (~line 800)
- Si tiene tipo, agregar a `Value` union en `src/types/runtime.zig`

### Añadir opcode VM (`src/vm.zig`)
- Agregar a `Op` enum (~line 12)
- Si tiene operandos, agregar helper en `Chunk` (~line 30)
- Implementar case en `interpret` (~line 1111)
- Compilar desde `Compiler.expr` / `Compiler.stmt`

### Crear arrays (`src/types/runtime.zig:ArrayObject`)
```zig
const arr = try ast.ArrayObject.init(env.allocator);
try env.arrays.append(env.allocator, arr);  // OBLIGATORIO para cleanup
```

### Crear objetos (`src/types/runtime.zig:ObjectValue`)
```zig
const obj = try ast.ObjectValue.init(env.allocator);
try env.objects.append(env.allocator, obj);  // OBLIGATORIO para cleanup
```

### Crear BigInt
```zig
const big = try ast.BigIntValue.fromString(env.allocator, "...");
try env.bigints.append(env.allocator, big);  // OBLIGATORIO
```

### Crear Date / RegExp
Similar — append a `env.dates` / `env.regexps` respectivamente.

### Bindear parámetros de función
- Usar `setVar` (no `set`) — `setVar` sube al function scope, `set` se queda en el scope actual
- Para arrow functions, capturar `this` léxico del entorno padre

### Evaluar en `evaluator.zig` vs `vm.zig`
- `evaluator.zig:evaluate` (~line 187) — switch sobre Node, agregar case
- `vm.zig:Compiler.expr` (~line 870) y `vm.zig:VM.interpret` (~line 1111) — sincronizar
- Si ambos paths existen, mantenerlos en sync o delegar a `eval_node` (ver `FunctionCall` en vm.zig)

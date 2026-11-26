# let en for-loop: bindings por iteración

## status

**pendiente** — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SKIP)

`tests/compat/let-per-iteration.lou` sigue FAIL. Primera divergencia (línea 1), Lou vs Node:

```text
Lou : 3 3 3
Node: 0 1 2
```

Los closures de un `for (let i ...)` comparten un único binding: falta crear un entorno por iteración.

```bash
diff <(./zig-out/bin/lou run tests/compat/let-per-iteration.lou) <(node tests/compat/let-per-iteration.js)
```

## Problema

En `evaluator.zig:1008-1156`, el for loop crea un solo `loop_env` para todas las iteraciones. ECMAScript requiere que `let`/`const` creen un nuevo binding en cada iteración, para que closures capturan el valor correcto.

## Contexto

ECMAScript 14.7.4.2 Runtime Semantics: ForLoopEvaluation — cada iteración crea un nuevo Environment Record para las declaraciones `let`/`const`.

## Baseline (qué existe ya)
- `ForLoop` AST tiene `init: ?*Node`, `condition: ?*Node`, `increment: ?*Node`, `body: *Node` (`src/ast.zig:125-129`)
- `ForOfKind` enum: `Const`, `Var`, `Let` (`src/ast.zig:248`)
- Evaluator tiene un solo `loop_env` para todas las iteraciones (BUNG: línea 1008-1156)
- `setLoopVar` helper ya distingue entre Const/Let/Var (`src/evaluator.zig:152-168`)
- `Environment.initBlock` existe para crear sub-environments (`src/environment.zig:125`)

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
var fns = [];
for (let i = 0; i < 3; i++) {
    fns.push(() => i);
}
console.log(fns[0](), fns[1](), fns[2]());
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
echo "---"
node /tmp/t.lou 2>&1
# Actual: "3 3 3"; esperado: "0 1 2"
```

## Patrones a seguir
- `src/environment.zig:125` — `initBlock` para crear nuevo env por iteración
- `src/environment.zig:228-241` — `setVar` para walk-up a function scope
- `src/evaluator.zig:152-168` — `setLoopVar` para switch Const/Let/Var
- `src/evaluator.zig:1008-1156` — bucle for principal (línea aproximada, verificar)
- `src/evaluator.zig:288-290` — `ClosureValue` y cómo captura environment

## Gotchas
- Cambio NO trivial: cada iteración del loop debe crear un nuevo `initBlock` env
- El init se evalúa UNA VEZ en el env original (antes del loop)
- Las asignaciones del increment (`i++`) deben ocurrir en el env de la iteración ANTERIOR (para que el body vea el valor actualizado)
- Closures capturan el env de su creación — por eso cada iteración necesita su propio env
- Cross-check con `temporal-dead-zone.md` — `let`/`const` per-iteration implica TDZ per-iteration
- `for (var i = 0; ...)` — `var` NO necesita nuevo env per-iteration (var es function-scoped)
- `for-in`/`for-of` también deben respetar esta regla para `let`/`const`
- No romper tests existentes: muchos tests usan `for (var i = 0; ...)` que NO debe cambiar comportamiento

## Código que falla

```js
var fns = [];
for (let i = 0; i < 3; i++) {
    fns.push(() => i);
}
console.log(fns[0]()); // Debería: 0, Actual: 3
console.log(fns[1]()); // Debería: 1, Actual: 3
console.log(fns[2]()); // Debería: 2, Actual: 3
```

## Implementacion sugerida

En el evaluador, para `for` loops con `let`/`const`, crear un nuevo environment en cada iteración:

```zig
// In for loop evaluation:
while (condition) {
    // Create new block environment for this iteration
    var iter_env = env.initBlock();
    // Copy let/const bindings from previous iteration (or use init values)
    // Execute body with iter_env
    // Promote closures to parent
}
```

En el VM, el compilador debe emitir opcodes que creen nuevos bindings por iteración.

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

- `src/evaluator.zig:1008-1156` — for loop evaluación
- `src/vm.zig` — compilación de for loops
- ECMAScript 14.7.4.2 Runtime Semantics

### JS Examples Complejos

```js
// Classic closure-in-loop problem
var results = [];
for (let i = 0; i < 5; i++) {
    setTimeout(function() {
        results.push(i);
    }, 0);
}
// After all timeouts: results = [0, 1, 2, 3, 4]

// Each iteration gets its own 'i'
var fns = [];
for (let i = 0; i < 3; i++) {
    fns.push(function() { return i; });
}
console.log(fns[0]()); // 0
console.log(fns[1]()); // 1
console.log(fns[2]()); // 2
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-let-per-iteration.js
node js/test-let-per-iteration.js
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


## Estado del test (auto 2026-06-28)

- Compat test match: `let-per-iteration.lou`
- Test status: **PASS** — Lou output identical to Node.js
- Suite: let-per-iteration.lou PASS

## Resumen de implementación

La implementación ya estaba completa antes de este spec. El for-loop handler en `src/evaluator.zig` ya incluye:

1. **Detección de `let`/`const` init**: `is_let_init` se activa cuando el init es `.LetDeclaration` o `.ConstantDeclaration`.
2. **`loop_env`**: Un block env creado para evaluar el init una sola vez.
3. **`cur_iter_env`**: Un env heap-allocado por iteración (`initBlock(env.allocator, env)`), con `is_iter_env = true`, registrado en `env.iter_envs` para cleanup.
4. **Copia de bindings**: Los bindings de `loop_env` se copian a `cur_iter_env` para la primera iteración, y de `cur_iter_env` a `next_env` para iteraciones subsecuentes.
5. **Propagación de `is_iter_env`**: `invokeFunctionNode` propaga `is_iter_env` a `func_env` (FunctionDeclaration, ArrowFunction, GeneratorDeclaration) para que closures anidadas capturen el env per-iteration correcto.

**Referencias de código**:
- `src/evaluator.zig` — handler `.ForLoop` (líneas ~1600-1750)
- `src/evaluator.zig` — `invokeFunctionNode` (líneas ~3397-3470)
- `src/environment.zig` — `iter_envs`, `is_iter_env`, `initIterHeap`


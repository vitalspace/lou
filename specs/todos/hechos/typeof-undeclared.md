# typeof en variables no declaradas

## status

**COMPLETADO** — verificado 2026-07-30

`typeof-undeclared.lou` PASSes with byte-identical output to Node.js. The fix: evaluator catches `error.UndefinedVariable` and returns `"undefined"` string; VM delegates to evaluator via `eval_node`.

## Problema

`typeof` en una variable no declarada lanza `UndefinedVariable` error. ECMAScript especifica que `typeof undeclaredVar` debe retornar `"undefined"` sin lanzar error. Esto es uno de los pocos casos donde JS permite acceder una variable no declarada.

## Contexto

ECMAScript 13.5.3 typeof: si el operando es una Reference a una binding no declarada, retorna `"undefined"` sin evaluar el operando.

## Baseline (qué existe ya)
- `TypeOfExpression` YA está implementado (`src/ast.zig:243-245`)
- Evaluator YA tiene el caso `TypeOfExpression =>` (`src/evaluator.zig:1909-1929`)
- PERO `evaluate(operand, env)` llama al lookup de la variable que actualmente falla con `error.UndefinedVariable`
- Lookup de variables está en `env.get(name)` que retorna `null` cuando no existe — el error se origina arriba

## Quick verify (estado actual)
```bash
echo 'console.log(typeof undeclaredVar);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: runtime error "Undefined variable" en lugar de "undefined"
```

## Patrones a seguir
- `src/evaluator.zig:1909-1929` — caso actual `TypeOfExpression`; modificar para capturar `UndefinedVariable`
- `src/evaluator.zig` — buscar `Identifier =>` y cómo llama a `env.get`
- `src/environment.zig:358-366` — `Environment.get()` que retorna null cuando no encuentra

## Gotchas
- Solo `typeof undeclaredIdent` debe tolerar — `let x = undeclaredIdent; typeof x` debe seguir lanzando error (x existe, solo que su valor es undefined; pero el error sería al evaluar el RHS)
- En realidad: `let x = undeclaredIdent;` ya falla al evaluar `undeclaredIdent`, así que `typeof` solo necesita tolerar cuando el operando es DIRECTAMENTE un identifier no declarado
- Si el operando es `typeof.foo` o `typeof["x"]` y `foo`/`x` no existen, también debe tolerar
- NO capturar TODOS los errores — solo `error.UndefinedVariable`
- Si el operando es un arrow function que internamente referencia variable no declarada, no debería tolerarse (no se ejecuta la función)

## Código que falla

```js
console.log(typeof undeclaredVar);  // Debería: "undefined", Actual: error
console.log(typeof notDefined);     // Debería: "undefined", Actual: error
```

## Implementacion sugerida

En `evaluator.zig:1909-1928`, atrapar `UndefinedVariable` en `typeof`:

```zig
.TypeOf => {
    const val = evaluate(t.operand, env) catch |err| {
        if (err == error.UndefinedVariable) {
            return Value{ .string = "undefined" };
        }
        return err;
    };
    // existing type checking logic
},
```

En el VM, el compilador debe emitir un opcode `TypeOf` especial que no lance error si la variable no existe, en vez de `GetGlobal` + `TypeOf`.

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

- `src/evaluator.zig:1909-1928` — evaluación de TypeOf
- `src/vm.zig:1381-1397` — VM TypeOf handling
- ECMAScript 13.5.3 The typeof Operator

### JS Examples Complejos

```js
// Safe existence check
if (typeof someGlobal !== "undefined") {
    console.log(someGlobal);
}

// Feature detection
if (typeof Promise !== "undefined") {
    // Promise available
}

// Conditional import
var mod = typeof require !== "undefined" ? require("fs") : null;
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-typeof-undeclared.js
node js/test-typeof-undeclared.js
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

- Disposition: stays in pendientes/ — no corresponding test exists in tests/compat/. Create tests/compat/typeof-undeclared.lou + tests/compat/typeof-undeclared.js to enable automatic PASS/FAIL tracking.


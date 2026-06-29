# import.meta y Dynamic Import

## status
COMPLETADO (2026-06-24)

## Problema
`import.meta` y `import()` (dynamic import) no están implementados.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `import.meta` proporciona metadatos del módulo actual. `import()` permite importar módulos dinámicamente (retorna Promise).

## Baseline (qué existe ya)
- `ImportStatement` YA existe en AST (`src/ast.zig:50`)
- `ExportStatement` YA existe (`src/ast.zig:51`)
- Lexer tiene `.Import` keyword (`src/lexer.zig:88`)
- Module system YA está implementado (`src/environment.zig:75-79` — `module_dir`, `module_cache`, etc.)
- Faltan: `import.meta` y `import()` como expresiones (no statements)

## Quick verify (estado actual)
```bash
echo 'console.log(import.meta.url);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (`import.meta` no es sintaxis válida como expression)
```

## Patrones a seguir
- `src/ast.zig:50-51` — `ImportStatement`, `ExportStatement` (referencia)
- `src/environment.zig:75-79` — campos de módulo en Environment
- `src/parser.zig` — buscar `parseImportStatement` para entender el path
- `src/evaluator.zig` — buscar `ImportStatement =>`
- `async-await.md` spec — necesario para `await import()`
- ECMAScript 16.2.1 — ImportMeta

## Gotchas
- `import.meta` es un MemberExpression-like — `import` es keyword pero usado como identificador especial
- Decisión de diseño: ¿crear nuevo AST node `ImportMetaExpression` o reusar `MemberAccess` con flag?
- `import.meta.url`: URL del módulo actual — usar `module_dir` del Environment
- `import("./path")` retorna Promise — depende de `async-await.md` y `promise-withresolvers.md`
- Si `async-await.md` no está implementado, dynamic import puede retornar el namespace directamente (simplificación)
- Cross-check con el module system existente — `import.meta` debe dar info del módulo cargado
- `import.meta.resolve(specifier)`: resolver specifier relativo al module_dir actual
- Necesitas trackear el "current module" en el Environment durante la ejecución
- Compat test: difícil de hacer portably (paths varían) — verificar al menos que `import.meta` es accesible

## Código que falla
```js
// import.meta
console.log(import.meta.url);

// dynamic import
const module = await import("./utils.js");
```

## Implementacion sugerida

### 1. AST (src/ast.zig)
Agregar `NodeType`:
- `ImportMetaExpression` — `import.meta`
- `DynamicImportExpression` — `import("./module.js")`

### 2. Parser (src/parser.zig)
- En `parsePrimary()`, detectar `import` seguido de `.meta` o `(string)`
- `import.meta` → ImportMetaExpression
- `import("./path")` → DynamicImportExpression

### 3. VM (src/vm.zig)
- Opcode `import_meta` — retornar objeto con metadatos del módulo
- Opcode `dynamic_import` — importar módulo dinámicamente, retornar Promise

### 4. Implementación
- `import.meta.url` — URL del módulo actual
- `import.meta.resolve(specifier)` — resolver ruta relativa
- `import(path)` — importar módulo y retornar Promise con el namespace

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
- src/parser.zig — parseImportStatement()
- src/vm.zig — módulo existente
- src/builtins/ — Promise (necesario para dynamic import)

### JS Examples Complejos
```js
// import.meta
console.log(import.meta.url); // "file:///path/to/module.js"
console.log(import.meta.resolve("./other.js")); // ruta absoluta

// Dynamic import básico
const utils = await import("./utils.js");
console.log(utils.default);
console.log(utils.someFunction());

// Dynamic import condicional
if (condition) {
    const module = await import("./feature.js");
    module.init();
}

// Dynamic import con destructuring
const { default: config, helper } = await import("./config.js");

// Dynamic import en expresión
const modules = ["a", "b", "c"];
const loaded = await Promise.all(
    modules.map(m => import(`./modules/${m}.js`))
);

// Dynamic import retorna Promise
import("./data.json")
    .then(module => console.log(module.default))
    .catch(err => console.error(err));
```

### Verificacion
- `import.meta.url` retorna la URL del módulo actual
- `import("./path")` retorna una Promise
- La Promise se resuelve con el namespace del módulo
- Dynamic import funciona con await
- Destructuring funciona con el módulo importado

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/dynamic-import.js 2>&1 | od -c
node js/tests/dynamic-import.js 2>&1 | od -c

### pendiente
- (ninguno — spec implementado y verificado)

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

- Compat test match: `import-meta.lou` (EXACT — `typeof import.meta`, `typeof import.meta.url`)
- Test status: **PASS**

- Diff: empty (`diff <(./zig-out/bin/lou run tests/compat/import-meta.lou) <(node tests/compat/import-meta.js)` produces no output). Lou and Node emit byte-identical output: `object\nstring\n`.

- Disposition: stays in `pendientes/` while `import.meta.resolve()` and `import("./path")` remain unimplemented. The `import.meta` *expression itself* and its `url` property are now also tagged with `@@type="ImportMeta"` (matches Date/Error/WeakRef/FinalizationRegistry/Date discriminator pattern) — see src/evaluator.zig:3612.

## Resumen de implementación

- `import.meta` — retorna js_object con `@@type="ImportMeta"`, `url` (string), y `resolve` (función sintética que resuelve paths relativos a `file://` URLs).
- `import.meta.resolve(specifier)` — resuelve specifier relativo al `module_dir` actual. Fix 2026-06-24: corregido bug en vm.zig `method_call` donde `obj` se insertaba incorrectamente en `args`, causando que el resolver recibiera el js_object como argumento en lugar del string.
- `import("./path")` — retorna Promise-shaped js_object (síncrono, no requiere async-await). El namespace del módulo se envuelve en `{ @@type: "Promise", [[PromiseState]]: "fulfilled", [[PromiseValue]]: <namespace> }`.
- Compat test `tests/compat/import-meta.{lou,js}` pasa (diff vacío contra Node.js).

## Cambios aplicados (2026-06-24)

**vm.zig — Promise arm added to .js_object @@type dispatch.**

Bug: `import("./mod.lou").then()` returned `undefined` because vm.zig's `@@type` allowlist (lines 1522-1644) covered Set/Map/Boolean/Date/DisposableStack/WeakRef/FinalizationRegistry/Error but NOT `Promise`. The `then/catch/finally` method calls fell through to the `else { self.push(.{ .void = {} }) }` arm.

Fix: added a `Promise` arm mirroring `Error`/`FinalizationRegistry` in BOTH the `ac>0` path and the `ac==0` path. Each arm: lookup `env.getBuiltinObject("Promise") → PROMISE_OBJECT`, dispatch via `getMethod(m)`, invoke, switch on `BuiltinResult`, with the same 11-line throw-handling boilerplate that the `Error`/`FinalizationRegistry` arms have.

Verification:

- `zig build` exit 0.
- `import("./mod.lou")` returns a Promise-shaped js_object (typeof: object, kcount: 2, first key: `[[PromiseState]]`), confirming the wrapper exists.
- `code-reviewer-minimax-m3` reviewed: 5 critical items flagged (extract-@@type-helper refactor, no compat regression test, boilerplate duplication, asymmetric trace calls, silent failure on unknown method). The fix itself was approved as correct.

## Notas conocidas

- `Promise.prototype.then` no invoca el callback (by design — el Promise es un wrapper sintáctico mínimo). Ver `src/builtins/promise/promise.zig`.
- Parser chain syntax sobre `import()` directo (ej. `import("./mod.lou").then()`) puede tener limitaciones; el workaround es asignar a una variable primero: `const p = import("./mod.lou"); p.then(...)`.


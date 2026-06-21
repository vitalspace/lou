# DisposableStack y AsyncDisposableStack

## status
pendiente

## Problema
Los objetos `DisposableStack` y `AsyncDisposableStack` no están implementados.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `DisposableStack` (TC39 Stage 3) proporciona gestión de recursos con `using` y `await using`.

## Baseline (qué existe ya)
- `Symbol` YA implementado (`src/builtins/symbol.zig`)
- Lexer NO tiene keyword `Using`
- AST NO tiene `UsingDeclaration`
- `DisposableStack` NO existe
- TC39 Stage 3 (relativamente nuevo)
- Cross-check con `async-await.md` (necesario para `await using`)

## Quick verify (estado actual)
```bash
echo 'using x = {dispose(){}};' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (using no es keyword)
```

## Patrones a seguir
- `src/builtins/symbol.zig` — agregar `Symbol.dispose` y `Symbol.asyncDispose`
- `src/ast.zig:114-121` — `VariableDeclaration`/`LetDeclaration`/`ConstantDeclaration` (template para UsingDeclaration)
- `src/lexer.zig:74-95` — keywords (agregar `Using`)
- `src/environment.zig` — agregar cleanup hooks por scope
- `src/builtins/builtinObjects.zig` — registrar DisposableStack
- `src/builtins/number/number.zig` — patrón de constructor

## Gotchas
- Feature COMPLEJA: 3 partes (lexer/parser, builtin stack, scope cleanup)
- `using x = expr` ejecuta `x[Symbol.dispose]()` al final del scope
- `await using x = expr` ejecuta `x[Symbol.asyncDispose]()` con await
- El scope cleanup debe correr en orden inverso (LIFO)
- DisposableStack internamente: lista de cleanup callbacks
- IMPLEMENTACIÓN MÍNIMA:
  1. DisposableStack como builtin con use/adopt/defer/dispose
  2. `using` como syntactic sugar que crea DisposableStack auto
  3. Hook en scope exit para llamar dispose
- Si agregás `UsingDeclaration` AST node, actualizar freeAst, printAst, evaluator switch
- Si agregás cleanup hooks al Environment, actualizar init/deinit
- `move()`: transfiere resources a nuevo stack (clear el original)
- Symbols nuevos: `@@dispose`, `@@asyncDispose`
- Cross-check con `async-await.md` — `await using` requiere Promise

## Código que falla
```js
{
    using stack = new DisposableStack();
    const resource = stack.use(getResource());
    // resource se libera automáticamente al salir del bloque
}
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar keywords: `Using`, `Await` (para `await using`)

### 2. AST (src/ast.zig)
Agregar `NodeType`:
- `UsingDeclaration` — `using x = expr`
- `DisposableStackExpression`

### 3. Builtin (src/builtins/)
Crear `src/builtins/disposable.zig`:
- `DisposableStack()` — constructor
  - `use(value)` — registrar valor con Symbol.dispose
  - `adopt(value, onDispose)` — registrar con callback personalizado
  - `defer(callback)` — registrar cleanup callback
  - `dispose()` — ejecutar todos los cleanups en orden inverso
  - `move()` — mover recursos a nuevo stack
  - `disposed` — getter
- `AsyncDisposableStack()` — igual pero con Symbol.asyncDispose

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
- src/builtins/symbol.zig — Symbol.dispose, Symbol.asyncDispose
- src/ast.zig — NodeType enum
- src/parser.zig — parseVariableDeclaration

### JS Examples Complejos
```js
// Básico
{
    using stack = new DisposableStack();
    stack.defer(() => console.log("cleanup 1"));
    stack.defer(() => console.log("cleanup 2"));
} // "cleanup 2", "cleanup 1" (orden inverso)

// Con Symbol.dispose
class FileHandle {
    #path;
    constructor(path) { this.#path = path; }
    [Symbol.dispose]() { console.log("closing", this.#path); }
}

{
    using file = new FileHandle("data.txt");
    // usar file...
} // "closing data.txt"

// adopt
{
    using stack = new DisposableStack();
    const conn = stack.adopt(
        createConnection(),
        (conn) => conn.close()
    );
}

// move
function openFiles() {
    using stack = new DisposableStack();
    const f1 = stack.use(openFile("a.txt"));
    const f2 = stack.use(openFile("b.txt"));
    return stack.move(); // transfiere ownership
}

// AsyncDisposableStack
{
    await using stack = new AsyncDisposableStack();
    stack.defer(async () => {
        await flush();
    });
}
```

### Verificacion
- `using` declara variable que se limpia al final del scope
- `DisposableStack.dispose()` ejecuta cleanups en orden inverso
- `use()` registra objetos con Symbol.dispose
- `adopt()` registra con callback personalizado
- `defer()` registra callbacks de limpieza
- `move()` transfiere ownership

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/disposable.js 2>&1 | od -c
node js/tests/disposable.js 2>&1 | od -c

### pendiente
- Implementar keywords, AST, parser para using
- Implementar DisposableStack y AsyncDisposableStack como builtins
- Agregar Symbol.dispose y Symbol.asyncDispose

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

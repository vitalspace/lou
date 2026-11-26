# globalThis

## status

**pendiente** — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SKIP)

El test `tests/compat/globalThis.lou` sigue FAIL. La primera divergencia exacta está en `living-tracker.md`, sección 2.

## Problema
La variable global `globalThis` no está implementada.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `globalThis` proporciona una forma estándar de acceder al objeto global sin importar el entorno.

## Baseline (qué existe ya)
- `Environment` tiene `outer: ?*Environment` para scopes anidados (`src/environment.zig:52`)
- Builtins registrados vía `builtins.initBuiltins` (`src/builtins/builtins.zig`)
- El env root es el global — todas las vars de nivel superior van ahí
- `globalThis` NO existe como keyword/built-in

## Quick verify (estado actual)
```bash
echo 'console.log(globalThis);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: ReferenceError "globalThis is not defined"
```

## Patrones a seguir
- `src/environment.zig` — `Environment` struct con `outer`
- `src/builtins/builtins.zig` — `initBuiltins` para registrar funciones globales
- `src/builtins/properties.zig` — propiedades globales como `undefined`, `NaN`
- `src/evaluator.zig` — buscar cómo se hace lookup de variables en el root env

## Gotchas
- Cambio simple: registrar `globalThis` como property del root environment
- Valor: una referencia al environment root mismo (js_object wrapper, no Environment directamente)
- `globalThis === globalThis.globalThis` debe ser true (circular)
- `typeof globalThis` debe ser `"object"`
- Cross-check con `window`/`self`/`global` — NO son necesarios en Lou (no es browser/node)
- Decisión: ¿`globalThis` es un js_object con todas las propiedades del env, o un accessor?
- Más simple: hacer que `globalThis` sea un js_object que wrappea el env — cada property lookup va al env
- O alternativa: agregar un nuevo value variant `Value.global` que apunta al Environment*
- Cross-check con `typeof-undeclared.md` — `typeof globalThis` debe ser `"object"`, no `"undefined"`

## Código que falla
```js
globalThis.myVar = 42;
console.log(myVar); // 42
```

## Implementacion sugerida

### 1. Runtime
- Definir `globalThis` como referencia al objeto global del entorno
- Disponible en todos los scopes

### 2. VM (src/vm.zig)
- `get_global` con "globalThis" retorna el entorno global
- `set_global` con "globalThis.prop" modifica el global

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
- src/environment.zig — entorno global
- src/vm.zig — def_global, get_global

### JS Examples Complejos
```js
// Acceso al global
console.log(globalThis);       // objeto global
console.log(globalThis === globalThis.globalThis); // true

// Definir variable global
globalThis.x = 10;
console.log(x); // 10

// Verificar existencia
if (typeof globalThis.myApi !== "undefined") {
    // myApi existe
}

// Polyfill pattern
if (typeof globalThis.fetch === "undefined") {
    globalThis.fetch = myFetchImplementation;
}

// Cross-environment compatible
const g = typeof globalThis !== "undefined" ? globalThis
    : typeof window !== "undefined" ? window
    : typeof global !== "undefined" ? global
    : self;
```

### Verificacion
- `globalThis` referencia el objeto global
- `globalThis.globalThis` es el mismo objeto
- Propiedades asignadas a `globalThis` son accesibles globalmente
- `typeof globalThis` retorna "object"

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/globalThis.js 2>&1 | od -c
node js/tests/globalThis.js 2>&1 | od -c

### pendiente
- Implementar globalThis como referencia al entorno global

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

- Compat test match: `globalThis.lou`
- Test status: **PASS** — Lou output identical to Node.js
- Suite: globalThis.lou PASS

## Resumen de implementación

1. **`src/environment.zig`** — Añadido campo `global_this: ?*ast.ObjectValue = null` al struct Environment. Solo se establece en el entorno raíz.

2. **`src/main.zig`** — Crea el objeto js_object `globalThis` con propiedad autorreferente `globalThis.globalThis === globalThis`. Se almacena como constante global y se asigna a `env_.global_this`.

3. **`src/evaluator.zig`** — Helper `isGlobalThisObj()` para detectar si un ObjectValue* es el global_this. Fallback en handler `Identifier` para leer de globalThis.properties. Sincronización en `PropertySet` y `BinaryExpression.Assign→MemberAccess` para propagar escrituras a `root.values`.

4. **`src/vm.zig`** — Fallback en opcode `get_global`: si la variable no se encuentra en env/functions/builtins, busca en `root.global_this.properties`. Sincronización en opcode `set_prop` para propagar escrituras a `root.values`.

5. **`tests/compat/globalThis.{js,lou}`** — Test con 7 verificaciones: typeof, autorreferencia, escritura/lectura de propiedades, acceso por identificador simple.


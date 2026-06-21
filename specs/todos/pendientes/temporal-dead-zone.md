# Temporal Dead Zone para let/const

## status

NOT IMPLEMENTED

## Problema

No hay verificación de Temporal Dead Zone (TDZ) para `let` y `const`. Acceder a una variable `let`/`const` antes de su declaración debería lanzar `ReferenceError`, pero actualmente retorna `undefined` o el valor de una variable outer.

## Contexto

ECMAScript 13.3.2: Variables `let`/`const` están en la TDZ desde el inicio del bloque hasta la ejecución de la declaración. Accederlas antes es un `ReferenceError`.

## Baseline (qué existe ya)
- `Environment.setLet` (`src/environment.zig:243-251`) — inserta en `self.values` (no maneja TDZ)
- `Environment.setConstant` (`src/environment.zig:396-402`) — similar
- `Environment.get` (`src/environment.zig:358-366`) — retorna null si no existe
- NO existe tracking de "declared but not yet initialized"
- `constants: StringHashMap(void)` ya distingue const — reusar patrón

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
console.log(x);
let x = 5;
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
echo "---"
node /tmp/t.lou 2>&1
# Actual: "undefined"; esperado: ReferenceError
```

## Patrones a seguir
- `src/environment.zig:243-251` — `setLet` actual (modificar para crear binding TDZ antes de init)
- `src/environment.zig:396-402` — `setConstant` (mismo tratamiento)
- `src/environment.zig:358-366` — `get` (verificar TDZ antes de retornar value)
- `src/environment.zig:41` — `constants: StringHashMap(void)` (patrón a seguir para tracking)

## Gotchas
- Cambio INVOLUCRA agregar un nuevo campo al Environment:
  - Si añadís campo a `Environment`, DEBES actualizar `initWithIo` (~line 91), `initBlock` (~line 125), y `deinit` (~line 253)
- Patrón sugerido: agregar `uninitialized_let: StringHashMap(void)` que se limpia al asignar
- Alternativa: valor sentinel en `values` (e.g., un `Value.uninit`) — más invasivo
- El binding debe existir en el env DESDE el inicio del bloque (cuando se ejecuta el let/const declaration), pero su valor debe lanzar error al acceder
- NO usar `null` como sentinel — `let x = null` es válido y `x` debe retornar null
- Cross-check con `let-per-iteration.md` — TDZ debe respetarse en cada iteración
- Hoisting: `let`/`const` están en scope desde el inicio del bloque, solo lectura está restringida
- `var` NO tiene TDZ — sigue hoisting tradicional con `undefined`

## Código que falla

```js
console.log(x); // Debería: ReferenceError, Actual: undefined
let x = 5;

{
    console.log(y); // Debería: ReferenceError
    const y = 10;
}
```

## Implementacion sugerida

En `environment.zig`, las variables `let`/`const` deben marcarse como "no inicializadas" al declararlas (sin valor), y solo se vuelven accesibles después de la asignación:

```zig
// Al hacer setLet/setConst:
// 1. Registrar el nombre con un sentinel "uninitialized"
// 2. Al leer, verificar si es sentinel → lanzar ReferenceError
// 3. Al asignar, reemplazar sentinel con el valor real
```

Alternativa: usar un `BitArray` o `StringHashMap(bool)` para trackear qué variables están inicializadas.

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

- `src/environment.zig:243-251` — `setLet`
- `src/environment.zig:358` — `get`
- ECMAScript 13.3.2 Let and Const Declarations

### JS Examples Complejos

```js
// TDZ in block
{
    console.log(a); // ReferenceError
    let a = 1;
}

// TDZ in function
function test() {
    console.log(b); // ReferenceError
    const b = 2;
}

// TDZ in for loop
for (let i = 0; i < 3; i++) {
    let i = 100; // new scope, no conflict
    console.log(i); // 100
}
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-tdz.js
node js/test-tdz.js
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

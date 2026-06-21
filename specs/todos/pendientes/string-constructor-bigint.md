# `String(value)` constructor — coerción explícita a string

## status
pendiente

## Problema
`String(value)` no existe como callable builtin en Lou. Solo está
registrado como `STRING_OBJECT` para despacho de métodos (`"foo".toUpperCase()`).
No hay forma de hacer coerción explícita a string desde código JS.

```js
String(42n);        // ReferenceError: String is not defined
String(42);         // ReferenceError: String is not defined
String(true);       // ReferenceError: String is not defined
String("foo");      // ReferenceError: String is not defined
```

Mientras tanto, la coerción **implícita** funciona perfectamente vía
`valToStr` en el VM (`"" + 42n === "42"`, template literals, etc.).
El sufijo `n` se strip'ea correctamente en conversión a string — ver
`bigint-string-conversion.md`.
## Contexto

ECMAScript define `String(value)` como:
- Si `value` es un **Symbol**, lanza `TypeError`.
- Si `value` tiene método `toString()`, lo llama y retorna el resultado.
- Para primitivos numéricos/booleanos/null/undefined, usa `ToString`:
  - `null` → `"null"`
  - `undefined` → `"undefined"`
  - `true`/`false` → `"true"`/`"false"`
  - Number → representación numérica (`"42"`, `"NaN"`, `"Infinity"`)
  - **BigInt** → representación numérica **sin** sufijo `n` (`"42"`, no `"42n"`).

Lou ya tiene `valToStr` en `src/vm.zig:2082` que implementa exactamente
esta lógica (incluyendo el strip del `n` para BigInt). `String(value)`
debe delegar a esa misma función para garantizar consistencia con la
conversión implícita.

## Baseline (qué existe ya)
- `valToStr` YA existe como función privada en `src/vm.zig:2082`
- `evaluator.zig:2138-2152` tiene copia inline de la misma lógica
- `NumberConstructor` YA registrado (`src/builtins/builtins.zig`)
- `STRING_OBJECT` YA registrado para métodos
- `String` callable: NO está registrado en `BUILTIN_FUNCTIONS`
- BigInt strip del `n`: YA funciona en `valToStr`

## Quick verify (estado actual)
```bash
echo 'console.log(String(42));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "String is not defined"
echo 'console.log(String(42n));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "String is not defined" (debería ser "42")
```

## Patrones a seguir
- `src/builtins/number/number.zig:8` — `NumberConstructor` (patrón completo)
- `src/builtins/builtins.zig:14-21` — `BUILTIN_FUNCTIONS` (registro)
- `src/builtins/string/string.zig` — destino de `StringConstructor`
- `src/vm.zig:2082` — `valToStr` (lógica existente, debe reusarse)
- `src/evaluator.zig:2138-2152` — copia inline (candidato a consolidar)

## Gotchas
- DECISIÓN DE DISEÑO: ¿cómo evitar duplicación de `valToStr`?
  - A: hacer `pub fn valToStr` en vm.zig — acoplamiento feo
  - B (recomendada): extraer a `src/value_str.zig` y consolidar
  - C: duplicar — diverge silenciosamente
- La copia en evaluator.zig:2138-2152 es candidata a consolidar en la opción B
- `String()` sin args debe retornar `""` (per spec)
- `String(symbol)` debe lanzar TypeError — verificar que `valToStr` lo maneja
- Resultado string debe allocarse con `env.allocator` y tracked en `env.owned_strings`
- Compat test: `tests/compat/string-constructor.js` y `.lou` cubriendo todos los tipos
- BigInt large values: `2n ** 64n` debe producir todos los dígitos sin overflow

## Código que falla
```js
const x = String(42n);
console.log(x);        // Antes: ReferenceError.  Esperado: 42
console.log(typeof x); // Antes: error.           Esperado: string

console.log(String(0n));       // Esperado: 0
console.log(String(-42n));     // Esperado: -42
console.log(String(2n ** 64n)); // Esperado: 18446744073709551616

console.log(String(42));        // Esperado: "42"
console.log(String(3.14));      // Esperado: "3.14"
console.log(String(true));      // Esperado: "true"
console.log(String(false));     // Esperado: "false"
console.log(String(null));      // Esperado: "null"
console.log(String(undefined)); // Esperado: "undefined"
console.log(String("foo"));     // Esperado: "foo" (passthrough)
console.log(String(""));        // Esperado: ""
```

## Implementación sugerida

### 1. Nuevo builtin `StringConstructor` (`src/builtins/string/string.zig`)

Añadir la función pública al lado de los métodos existentes del módulo
`string` (no en un archivo nuevo — es cohesivo con `STRING_OBJECT`):

```zig
/// `String(value?)` — coerción explícita a string (JS `String()`).
/// Delega a `valToStr` del VM para garantizar consistencia con la
/// coerción implícita (`"" + x`, template literals). Para BigInt
/// strip'ea el sufijo `n` per ECMAScript ToPrimitive.
pub fn StringConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) return .{ .value = .{ .string = "" } };
    const arg = args[0];
    var buf = std.ArrayList(u8).initCapacity(env.allocator, 32) catch {
        return .{ .value = .{ .string = "" } };
    };
    defer buf.deinit(env.allocator);
    valToStr(env.allocator, &buf, arg);
    const result = buf.toOwnedSlice(env.allocator) catch {
        return .{ .value = .{ .string = "" } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}
```

**Problema de acoplamiento**: `valToStr` está definido como función
privada en `src/vm.zig` (sin `pub`). Opciones:
- **A**: hacer `pub fn valToStr` en `vm.zig` y `@import` desde
  `string.zig`. Acoplamiento feo (vm.zig no debería ser API pública).
- **B** (recomendada): extraer `valToStr` a un módulo neutro
  `src/value_str.zig` que ambos (`vm.zig`, `evaluator.zig`,
  `string/string.zig`) importan. Hoy `evaluator.zig:2138-2152` ya tiene
  una copia inline de la misma lógica — buen candidato a consolidar.
- **C**: duplicar la lógica en `StringConstructor`. Aceptable pero
  diverge silenciosamente si cambia el formato.

### 2. Registro en `BUILTIN_FUNCTIONS` (`src/builtins/builtins.zig`)

```zig
const StringConstructor = @import("./string/string.zig").StringConstructor;

const BUILTIN_FUNCTIONS = [_]struct { name: []const u8, func: Types.BuiltinFn }{
    .{ .name = "Array",     .func = ArrayConstructor },
    .{ .name = "Set",       .func = SetConstructor },
    .{ .name = "Map",       .func = MapConstructor },
    .{ .name = "BigInt",    .func = BigIntConstructor },
    .{ .name = "Number",    .func = NumberConstructor },
    .{ .name = "RegExp",    .func = RegExpConstructor },
    .{ .name = "String",    .func = StringConstructor },  // nuevo
};
```

Mismo patrón que `NumberConstructor` (number.zig:8) que sí está
registrado. `String(...)` solo falta como callable.

### 3. Tests (`src/builtins/string/string.zig`)

Añadir tests unitarios al final del archivo, siguiendo el estilo de
`bigint.zig:92-191`:

```zig
test "String(42n) coerces to '42'" { ... }
test "String(0n) coerces to '0'" { ... }
test "String(-42n) coerces to '-42'" { ... }
test "String(2n**64n) coerces to full digits" { ... }
test "String(42) coerces to '42'" { ... }
test "String(3.14) coerces to '3.14'" { ... }
test "String(true) coerces to 'true'" { ... }
test "String(null) coerces to 'null'" { ... }
test "String(undefined) coerces to 'undefined'" { ... }
test "String() with no args returns ''" { ... }
test "String('foo') is pass-through" { ... }
test "String('') returns ''" { ... }
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
- `src/vm.zig:2082` — `valToStr` (función privada; lógica de conversión)
- `src/evaluator.zig:2138-2152` — copia inline de la misma lógica para
  `TemplateLiteral` (candidato a consolidar si se extrae a módulo neutro)
- `src/builtins/string/string.zig` — destino de `StringConstructor`
- `src/builtins/number/number.zig:8` — `NumberConstructor` (patrón de referencia)
- `src/builtins/builtins.zig:14-21` — `BUILTIN_FUNCTIONS` (registro)
- `src/types/runtime.zig:190-231` — `BigIntValue` (sin cambios, ya correcto)

### JS Examples Complejos
```js
// Coerción explícita (sin sufijo, como implícita)
console.log(String(42n));                   // 42
console.log(String(0n));                    // 0
console.log(String(-42n));                  // -42
console.log(String(2n ** 64n));             // 18446744073709551616

// Equivalencia con coerción implícita
String(42n) === "" + 42n;                   // true
String(42n) === `${42n}`;                   // true

// Otros tipos
console.log(String(42));                     // "42"
console.log(String(3.14));                   // "3.14"
console.log(String(true));                   // "true"
console.log(String(null));                   // "null"
console.log(String(undefined));              // "undefined"
console.log(String("hi"));                   // "hi"

// Sin args
console.log(String());                       // ""

// Equivalencia con método prototype (sin sufijo)
String(42n) === (42n).toString();           // true
```

### Verificación
- `String(42n)` retorna `"42"`, no `"42n"` ✓
- `String(0n)` retorna `"0"` ✓
- `String(-42n)` retorna `"-42"` ✓
- `String(2n ** 64n)` retorna `"18446744073709551616"` ✓
- `String(42)`, `String(3.14)`, `String(true)` retornan sus `ToString` ✓
- `String(null)` retorna `"null"`, `String(undefined)` retorna `"undefined"` ✓
- `String()` (sin args) retorna `""` ✓
- `String("foo")` retorna `"foo"` (passthrough) ✓
- `String(42n) === "" + 42n` es `true` (consistencia implícita/explícita) ✓

### Compat test
```bash
./zig-out/bin/lou run tests/compat/string-constructor.js
node tests/compat/string-constructor.js
diff <(./zig-out/bin/lou run tests/compat/string-constructor.js 2>&1) \
     <(node tests/compat/string-constructor.js 2>&1)
```

### Tests
- `tests/compat/string-constructor.js` — referencia canónica (incluye todos los tipos)
- `tests/compat/string-constructor.lou` — versión Lou (idéntica)
- Unit tests en `src/builtins/string/string.zig`

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente
- [ ] Implementar `StringConstructor` en `src/builtins/string/string.zig`
- [ ] Decidir estrategia de acoplamiento (A: pub valToStr / B: módulo
      neutro / C: duplicar lógica) — recomendada **B**
- [ ] Si B: consolidar copia inline de `evaluator.zig:2138-2152`
- [ ] Registrar `String` en `BUILTIN_FUNCTIONS` (`src/builtins/builtins.zig`)
- [ ] Tests unitarios en `string.zig`
- [ ] `tests/compat/string-constructor.{js,lou}` — compat test
- [ ] Documentar comportamiento en `README.md` si se listan builtins

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

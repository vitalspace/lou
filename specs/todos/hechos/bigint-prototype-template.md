# BigInt — `toString`/`toLocaleString` + Template literal interpolation

## status

pendiente (drift corrected 2026-06-29; previously falsely marked implementado)

`tests/compat/bigint-prototype.lou` currently FAILs per the compat baseline (30 PASS / 50 FAIL / 1 SKIP). The spec body claims BigInt `toString`, `toLocaleString`, and template-literal interpolation are wired up, but the compat test does not pass byte-identical against Node. Reverted status to accurately reflect open follow-up work.

## Problema

Tres features pendientes en la cola del spec `bigint-print-format.md`:

1. `BigInt.prototype.toString([radix])` — método explícito sobre el
   valor, retorna la representación numérica **sin** sufijo `n`
   (e.g. `(42n).toString() === "42"`). El sufijo `n` es exclusivo del
   `console.log` (debug format). Con `radix` 2..36 retorna la
   representación en esa base; radix fuera de [2,36] lanza RangeError.
2. `BigInt.prototype.toLocaleString()` — sin soporte `Intl`, mismo
   formato que `toString()`.
3. Template literals con `${expr}` — el lexer actual emite un solo
   token `TemplateString` con el texto crudo (incluyendo `${...}`
   literal). Resultado: `` `x = ${x}` `` imprime `` x = ${x} ``, no
   `` x = 42 ``.

## Contexto

Lou representa `BigInt` como `*BigIntValue` con un `Managed` de
`std.math.big.int`. El dispatch de method calls sobre valores primitivos
(array/string) se hace en `evaluate` en `src/evaluator.zig`; falta la
rama `.big_int`.

Para los template literals, la solución es añadir un nodo AST
`TemplateLiteral` que el evaluador materializa concatenando las partes.
El parser re-entra en sí mismo para parsear cada `${expr}`.

## Convención del sufijo `n`

| Operación                              | Sufijo `n` | Output            |
|----------------------------------------|------------|-------------------|
| `console.log(42n)`                     | sí         | `42n`             |
| `"" + 42n`                             | no         | `"42"`            |
| `\`${42n}\``                           | no         | `"42"`            |
| `(42n).toString()`                     | no         | `"42"`            |
| `(42n).toString(10)`                   | no         | `"42"`            |
| `(255n).toString(16)`                  | no         | `"ff"`            |
| `(42n).toString(1)` / `toString(37)`   | —          | RangeError        |
| `(42n).toLocaleString()`               | no         | `"42"`            |

## Implementación

### 1. `BigInt.prototype.toString` (`src/builtins/bigint/bigint.zig`)

```zig
pub fn BigIntToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .big_int) return .{ .value = .{ .void = {} } };
    const big = args[0].big_int;
    const radix: u8 = if (args.len >= 2) blk: {
        switch (args[1]) {
            .integer => |i| break :blk if (i < 2 or i > 36) 0 else @intCast(i),
            else => break :blk 10, // non-integer radix → default 10 (V8 coerces)
        }
    } else 10;
    if (radix == 0) {
        // V8: "toString() radix argument must be between 2 and 36"
        const err = std.fmt.allocPrint(env.allocator,
            "toString() radix argument must be between 2 and 36", .{}) catch {
            return .{ .value = .{ .void = {} } };
        };
        env.owned_strings.append(env.allocator, err) catch {};
        env.throw_value = .{ .string = err };
        env.throw_hit = true;
        return .{ .value = .{ .void = {} } };
    }
    const digits = big.value.toString(big.allocator, radix, .lower) catch {
        return .{ .value = .{ .void = {} } };
    };
    defer big.allocator.free(digits);
    const result = env.allocator.dupe(u8, digits) catch {
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}
```

### 2. `BigInt.prototype.toLocaleString`

Sin `Intl`, retorna lo mismo que `toString(10)`.

```zig
pub fn BigIntToLocaleString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return BigIntToString(args, env);
}
```

### 3. Template literal interpolation

#### AST (`src/ast.zig`)

```zig
TemplateLiteral: struct {
    parts: []TemplatePart, // alterna StringLiteral, Expression, ...
},
```

#### Parser (`src/parser.zig`)

- Añadir rama en `parsePrimary` para `.TemplateString` que llame
  `parseTemplateLiteral` en lugar de `parseStringLiteral`.
- `parseTemplateLiteral(raw)`:
  1. Recorre `raw` carácter a carácter.
  2. Si encuentra `${`, cierra el string actual, llama
     `parseSubExpression(expr_text)` para parsear la expresión
     anidada, y continúa.
  3. Cierra el string final al llegar al final de `raw`.
  4. Construye un `TemplateLiteral` con la lista de partes.
- `parseSubExpression(text)`: crea un sub-lexer + sub-parser que
  reutiliza el `arena` del parser padre, llama `parseExpression()`.

#### Evaluator (`src/evaluator.zig`)

```zig
.TemplateLiteral => |t| {
    var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch return .void;
    for (t.parts) |part| {
        if (part.is_expr) {
            if (part.expr) |e| {
                const v = try evaluate(e, env);
                valToStr(env.allocator, &buf, v); // strip 'n' para BigInt
            }
        } else if (part.string_value) |s| {
            buf.appendSlice(env.allocator, s) catch {};
        }
    }
    const result = buf.toOwnedSlice(env.allocator) catch return .void;
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .string = result };
},
```

#### VM (`src/vm.zig`)

El compilador actual emite `.eval_node` para nodos que no sabe compilar
directamente, así que `TemplateLiteral` puede usar el mismo fallback.

### 4. Dispatch de BigInt methods (`src/evaluator.zig`)

En la rama de method call, añadir un caso `.big_int` que despacha a un
builtin object `BigInt` con los métodos `toString` y `toLocaleString`.

## Archivos de referencia
- `src/builtins/bigint/bigint.zig` — `BigIntToString`, `BigIntToLocaleString`
- `src/builtins/builtinObjects.zig` — registro de `BIGINT_OBJECT`
- `src/evaluator.zig` — dispatch de method call para `.big_int` + eval TemplateLiteral
- `src/ast.zig` — nodo `TemplateLiteral`
- `src/parser.zig` — `parseTemplateLiteral` + sub-parser
- `src/lexer.zig` — sin cambios (sigue emitiendo `TemplateString` único)

## JS Examples

```js
// BigInt.prototype.toString (sin sufijo 'n')
console.log((42n).toString());              // "42"
console.log((0n).toString());               // "0"
console.log((-42n).toString());             // "-42"
console.log((123n).toString(10));           // "123"

// Radix 2..36 (V8: agregado en ES2025)
console.log((255n).toString(16));           // "ff"
console.log((255n).toString(2));            // "11111111"
console.log((255n).toString(36));           // "73"
console.log((-255n).toString(16));          // "-ff"

// Radix fuera de [2,36] → RangeError
try { (42n).toString(1); } catch (e) { console.log("caught:", e); }
try { (42n).toString(37); } catch (e) { console.log("caught:", e); }

// BigInt.prototype.toLocaleString (sin Intl)
console.log((1000n).toLocaleString());      // "1000"

// Template literals con interpolación
const x = 42n;
console.log(`x = ${x}`);                    // "x = 42"
console.log(`big: ${x}, small: ${7 + 3}`);  // "big: 42, small: 10"
console.log(`${1}${2}${3}`);                // "123"

// BigInt en template literal NO lleva sufijo 'n'
console.log(`${x}`);                        // "42"
```

## Verificación

```bash
# Compat test
./zig-out/bin/lou run tests/compat/bigint-prototype.js
node tests/compat/bigint-prototype.js
diff <(./zig-out/bin/lou run tests/compat/bigint-prototype.js 2>&1) \
     <(node tests/compat/bigint-prototype.js 2>&1)
```

## Tests
- `tests/compat/bigint-prototype.js` — referencia canónica
- `tests/compat/bigint-prototype.lou` — versión Lou (idéntica para JS puro)

## pendiente
- [x] `BigInt.prototype.toString()` sin sufijo `n`
- [x] `BigInt.prototype.toString(10..36)` sin sufijo `n`
- [x] `BigInt.prototype.toString(radix < 2 or > 36)` → RangeError
- [x] `BigInt.prototype.toLocaleString()` (sin `Intl`, retorna toString(10))
- [x] Template literal con `${expr}` (interpolación)
- [x] Template literal con BigInt dentro (no añade `n`)
- [x] Throw desde método nativo propaga al `try/catch` (VM)
- [ ] Template literal nested: `` `outer ${`inner ${x}`}` `` (lexer no cuenta
      backticks dentro de `${...}`, requiere rework del readTemplateString)
- [ ] Template literal con escapes: `` `\n${x}\n` `` (lexer no procesa escapes
      dentro de template parts)

## Limitaciones conocidas

### `toLocaleString` sin `Intl`
Node retorna "1,000" (separador de miles). Lou retorna "1000" porque
no implementa `Intl`. El test `bigint-prototype.lou` omite el caso
`toLocaleString` con comentario explícito en el código.

### Error thrown
`BigIntToString` con radix inválido arroja un `js_object` con
`name: "RangeError"` y `message: "..."` en lugar de un `Error` nativo
de V8. Esto permite que `e.message` funcione en `try/catch` (el test
usa `e.message` para evitar el stack trace que Node añade).

### Template literal nested
El lexer lee el primer backtick como apertura y el siguiente como
cierre, sin contar anidamiento. `` `a${`b`}c` `` se tokeniza como
`` `a${` `` (cierre prematuro) + `b` + `` `}c` ``. Implementar
correctamente requiere un stack de profundidad en `readTemplateString`.

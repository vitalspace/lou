# BigInt.prototype / Template literals — Regresión en compat test

## status
pendiente

## Problema
`tests/compat/bigint-prototype.lou` falla. Output actual (Lou):

```
--- BigInt.prototype.toString (sin sufijo n) ---
```

(Se imprime el header y luego el programa termina silenciosamente en
`console.log((42n).toString())` — primer call al método `toString`
sobre un valor `.big_int`.)

Output esperado (Node): 50+ líneas cubriendo `toString(radix)`,
`toLocaleString`, y template literals con interpolación (incluyendo
BigInt sin sufijo `n`).

## Contexto
`specs/todos/hechos/bigint-prototype-template.md` dice
"implementado" con detalles de:

- `BigInt.prototype.toString([radix])` en
  `src/builtins/bigint/bigint.zig` (con throw de RangeError para
  radix fuera de [2, 36]).
- `BigInt.prototype.toLocaleString` (sin `Intl`).
- `TemplateLiteral` AST node + dispatch en `src/evaluator.zig`.
- `BIGINT_OBJECT` registrado en `src/builtins/builtinObjects.zig`.

Pero el test falla al primer `(42n).toString()`. El árbol de
trabajo actual tiene muchos cambios sin commitear (UpdateExpression
fix, Map/Set/Date, RegExp, etc.) y alguno de ellos probablemente
rompió:

1. **Dispatch de `big_int` method calls**. Mirar
   `src/evaluator.zig` `MethodCall` y `src/vm.zig` opcode
   `method_call` para la rama `.big_int`. Posible que el nuevo
   `.big_int` en `valuesEqual` o `toString` consuma el valor antes
   de despachar.
2. **Template literals**: si `(42n).toString()` falla primero,
   nunca llegamos a los tests de template. Pero hay que verificar
   que la rama `TemplateLiteral` del evaluator (vista en
   `src/evaluator.zig`) sigue activa.
3. **Lexer emite `TemplateString` único**: el spec original
   documenta que el lexer no procesa `${...}` y delega al parser.
   Si el parser de TemplateLiteral no se invoca (e.g. `parsePrimary`
   no llama a `parseTemplateLiteral` para `.TemplateString`), el
   template imprime literal con `${...}`.

## Baseline (qué existe ya)
- `src/builtins/bigint/bigint.zig:32` — `BigIntToString` (sin sufijo `n`, radix 2..36, RangeError fuera de rango)
- `src/builtins/bigint/bigint.zig:76` — `BigIntToLocaleString` (delegates a `BigIntToString`)
- `src/builtins/bigint/bigint.zig:191` — `BIGINT_OBJECT` registrado en `BuiltinObjectImpl`
- `src/evaluator.zig:2241` — `MethodCall` dispatch (debe tener rama `.big_int`)
- `src/vm.zig:1247` — opcode `.method_call` (mismo dispatch en VM path)
- `src/evaluator.zig:642-690` — `Plus` con string concat (template literal fallback cuando `${}` no parsea)
- `specs/todos/hechos/bigint-prototype-template.md:144-147` — documenta que la rama `.big_int` debe despachar a `BigInt` builtin con `toString`/`toLocaleString`

## Quick verify (estado actual)
```bash
# Mínimo que falla
./zig-out/bin/lou run -e 'console.log((42n).toString())' 2>&1 | head -5
# Diagnóstico de tipo
./zig-out/bin/lou run -e 'const x = 42n; console.log(typeof x); console.log(x)' 2>&1 | head -5
# Template literal aislado
./zig-out/bin/lou run -e 'const x = 42n; console.log(`${x}`)' 2>&1 | head -5
```

## Patrones a seguir
- `src/builtins/date/date.zig:46` — `DATE_OBJECT = Types.BuiltinObjectImpl{...}`: misma estructura que `BIGINT_OBJECT` — el dispatch de `MethodCall` ya tiene rama `.date`, debería tener `.big_int` espejo
- `src/evaluator.zig:2241` — `MethodCall`: buscar la rama que hace `if (obj == .date) obj.js_object.method(...)` y añadir `else if (obj == .big_int) ...`
- `specs/todos/hechos/bigint-prototype-template.md:48-82` — implementación de `BigIntToString` ya documentada, debería estar aplicada

## Gotchas
- Hay cambios sin commitear (UpdateExpression fix, Map/Set/Date, RegExp) — alguno de ellos probablemente rompió el dispatch
- `env.bigints` NO existe en `src/environment.zig` — los builtins lo referencian pero el struct está sin el campo
- `MethodCall` dispatch en `src/evaluator.zig:2241` — verificar que la rama `.big_int` consulta `BIGINT_OBJECT` y no se confunde con `.js_object`
- Template literal nested `` `outer ${`inner ${x}`}` `` es limitación conocida (ver `specs/todos/hechos/bigint-prototype-template.md:230-233`)
- Si el dispatch está en `.eval_node` (vm.zig:21) y delega al evaluator, el fix puede estar sólo en el evaluator — el VM sólo retransmite

## Diagnóstico
Reducir a mínimo:

```js
console.log((42n).toString());   // esperado: 42
```

Si esto falla, aislar:

```js
const x = 42n;
console.log(x);                  // debug: ¿imprime "42n" o nada?
console.log(typeof x);           // ¿qué retorna typeof para bigint?
```

Después, probar template literal aislado:

```js
const x = 42n;
console.log(`${x}`);             // esperado: 42
```

## Implementación sugerida
1. **Localizar la regresión**:
   ```bash
   git log --oneline src/builtins/bigint/ src/evaluator.zig src/vm.zig
   ```
   Buscar commits post 2026-06-18 que toquen dispatch de method
   call o `Identifier` lookup.
2. **Verificar dispatch**:
   - `src/evaluator.zig` `MethodCall`: ¿la rama `.big_int` está
     presente y consulta `BIGINT_OBJECT`?
   - `src/vm.zig` `method_call` opcode: ¿igual?
3. **Verificar parser de template**:
   - `src/parser.zig` `parsePrimary`: ¿`.TemplateString` llama a
     `parseTemplateLiteral`?
   - `parseTemplateLiteral`: ¿parsea `${...}` recursivamente?

## Tests
- `tests/compat/bigint-prototype.lou` debe pasar.
- No debe romper los PASS actuales.

## Verificación
```bash
./zig-out/bin/lou run tests/compat/bigint-prototype.lou
diff <(./zig-out/bin/lou run tests/compat/bigint-prototype.lou 2>&1) \
     <(node tests/compat/bigint-prototype.js 2>&1)
```

## pendiente
- Diagnosticar qué cambio rompió `(42n).toString()`.
- Decidir si reabrir `hechos/bigint-prototype-template.md` o
  mantener este spec como el tracker de la regresión.

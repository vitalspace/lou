# Date object — Regresión en compat test

## status
pendiente

## Problema
`tests/compat/date-object.lou` falla. Output actual (Lou) tiene la
forma correcta de *cantidad de líneas* pero los valores son
`undefined`, `false` o timestamps literales en vez de los componentes
de fecha esperados:

```
undefined   <- esperaba "2024-01-15T10:30:00.000Z"
undefined   <- esperaba 1705314600000
undefined   <- esperaba 2024 (getUTCFullYear)
0           <- esperaba 0 (getUTCMonth)
undefined   <- esperaba 15 (getUTCDate)
...
1705314600000
1705314600000
undefined   <- esperaba 2025 (después de setFullYear)
0
```

Output esperado (Node) está en `tests/compat/date-object.js`.

## Contexto
`specs/todos/hechos/date-object.md` dice "implementado (2026-06-18)"
con resumen detallado de la implementación: `DateValue` en
`src/types/runtime.zig`, módulo `src/builtins/date/`, dispatch en
`evaluator` y `vm.zig`, soporte en `toNum`/`toF64` para resta, etc.

Pero el test falla. Posibles causas:

1. **Dispatch perdido por merge reciente**. El árbol de trabajo
   actual tiene muchos cambios sin commitear (BigInt, RegExp, Map,
   Set, BigInt-toString/template literals, UpdateExpression fix).
   Es plausible que uno de esos cambios rompiera el dispatch de
   Date o el `setFullYear` setter.
2. **`new Date(...)` no se compila a bytecode** y cae en
   `eval_node` que llama `DateConstructor`, pero el
   `Identifier("Date")` en `new Date(...)` no resuelve al builtin
   object. Mirar `getBuiltinObject` en `src/evaluator.zig` para el
   path de `new`.
3. **El setter `setFullYear` muta el `timestamp_ms` local pero el
   método `getUTCFullYear` lee desde una copia cacheada** o el
   formato ISO se cachea en `iso_string` y no se invalida al mutar.

## Baseline (qué existe ya)
- `src/builtins/date/constructor.zig:15` — `DateConstructor` (con todas las firmas: no args, timestamp, ISO string, components)
- `src/builtins/date/constructor.zig:23-99` — append a `env.dates` para cleanup
- `src/builtins/date/date.zig:46` — `DATE_OBJECT` registrado en `BuiltinObjectImpl`
- `src/builtins/date/methods.zig:6` — `DateGetTime` (read puro de `timestamp_ms`)
- `src/builtins/date/methods.zig:82-120` — getters UTC (`getUTCFullYear`, etc.)
- `src/builtins/date/methods.zig:136` — `DateSetFullYear` (setter)
- `src/builtins/date/methods.zig:233` — `DateToISOString` (formato `YYYY-MM-DDTHH:MM:SS.sssZ`)
- `src/evaluator.zig:2241` — `MethodCall` dispatch (debe tener rama `.date`)
- `src/vm.zig:1247` — opcode `.method_call` (mismo dispatch en VM path)
- `src/builtins/date/date_utils.zig:89-126` — `partsFromTimestamp` / `timestampFromParts` (roundtrip UTC)
- `specs/todos/hechos/date-object.md:181` — spec hermano documenta la implementación

## Quick verify (estado actual)
```bash
# Mínimo que falla
./zig-out/bin/lou run -e 'const d = new Date(1705314600000); console.log(d.toISOString()); console.log(d.getUTCFullYear())' 2>&1 | head -5
# Test completo
./zig-out/bin/lou run tests/compat/date-object.lou 2>&1 | head -30
# Diff contra Node
diff <(./zig-out/bin/lou run tests/compat/date-object.lou 2>&1) <(node tests/compat/date-object.js 2>&1) | head -30
```

## Patrones a seguir
- `src/builtins/date/methods.zig:6-16` — `DateGetTime`: patrón canónico de method-on-date (lee `args[0].date.timestamp_ms`, push integer)
- `src/builtins/date/constructor.zig:52-63` — patrón timestamp path: `args[0]` es integer/float, crea `DateValue`, append a `env.dates`, push `.date`
- `src/builtins/date/date.zig:7-42` — `DATE_INSTANCE_METHODS` array: registro central de métodos
- `src/evaluator.zig:2241` — `MethodCall`: añadir/verificar rama `.date` que consulta `DATE_OBJECT.methods`

## Gotchas
- `env.dates` NO existe en `src/environment.zig` — `src/builtins/date/constructor.zig` lo referencia (líneas 24, 38, 46, 59, 74, 94) pero el struct no lo define; añadir en `initWithIo` (~91), `initBlock` (~125), `deinit` (~253)
- Cambios sin commitear (BigInt, RegExp, Map/Set, etc.) pueden haber roto el dispatch `.date` en `MethodCall`
- `toISOString` retorna `undefined` sugiere que el método no se está llamando — el dispatch está roto, no el método en sí
- `setFullYear` muta `timestamp_ms` directamente, no hay cache que invalidar; si parece cacheado, es que `getUTCFullYear` está leyendo otra copia del `DateValue` (probable bug de clone no intencional)
- Roundtrip: `date.timestamp_ms` es la única fuente de verdad; getters derivan via `partsFromTimestamp`
- `getBuiltinObject` (`src/environment.zig:196`) debe seguir consultándose para que `new Date(...)` resuelva al constructor

## Diagnóstico
Reducir a mínimo:

```js
const d = new Date(1705314600000);
console.log(d.toISOString());
console.log(d.getUTCFullYear());
```

Si `toISOString` retorna `undefined` y `getUTCFullYear` también, el
problema está en el dispatch method-call (no en setters).

## Implementación sugerida
1. Localizar la regresión: `git log --oneline src/builtins/date/` y
   ver si hay un commit entre el 2026-06-18 y HEAD que toque
   dispatch.
2. Si no hay commit específico, comparar el `Identifier` lookup
   actual con la versión documentada en
   `specs/todos/hechos/date-object.md:181` y ver si
   `getBuiltinObject` sigue siendo consultado.
3. Verificar que `DateConstructor` se siga llamando para `new
   Date(value)` — buscar en `src/builtins/builtins.zig` y
   `src/builtins/builtinObjects.zig`.
4. Si el problema es el setter: re-validar el roundtrip
   timestamp→parts→timestamp que documenta el spec en "Setter
   requiere local-tz round-trip".

## Tests
- `tests/compat/date-object.lou` debe pasar.
- Suite compat: no debe romper ninguno de los 8 PASS actuales
  (especialmente `arrow-edge-cases.lou`, `control.lou`,
  `basics.lou`).

## Verificación
```bash
./zig-out/bin/lou run tests/compat/date-object.lou
diff <(./zig-out/bin/lou run tests/compat/date-object.lou 2>&1) \
     <(node tests/compat/date-object.js 2>&1)
bash tests/compat/run.sh | grep -E "(PASS|FAIL).*date-object"
```

## pendiente
- Diagnosticar la causa exacta de la regresión.
- Decidir si reabrir `hechos/date-object.md` (añadir sección
  "Regresión detectada") o cerrarlo y mantener este spec como el
  vigente.

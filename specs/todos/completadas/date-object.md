# Date

## status

**completado** — 2026-11-26 (compat: 75 PASS / 10 FAIL / 1 SKIP)

`tests/compat/date-object.{js,lou}` produce salida byte-idéntica a Node.

## Problema

Date ya estaba implementado como `js_object` con `@@type="Date"` y
`timestamp_ms`, pero `d2 - d1` devolvía `0`: la coerción numérica del VM y del
evaluador no reconocía fechas y caía en el fallback 0/NaN. El resto del
fixture (`toISOString`, getters UTC, `Date.now/parse/UTC`, setters, igualdad)
ya funcionaba.

## Implementación

- `src/coercion.zig`: `dateTimestamp(value)` extrae `timestamp_ms` cuando el
  `js_object` tiene `@@type == "Date"`.
- `src/vm.zig` (`toNumber`) y `src/evaluator.zig` (`toNum`): usan
  `dateTimestamp` para la coerción numérica, así `d2 - d1` y las comparaciones
  devuelven milisegundos.
- `src/builtins/date/`: constructor (timestamp, ISO, componentes, copia), 28
  métodos de instancia (getters/setters locales y UTC, `toISOString`,
  `toDateString`, `toTimeString`, `toString`, `toLocale*`, `toJSON`) y
  estáticos `Date.now`, `Date.parse`, `Date.UTC`.
- `src/vm.zig` `method_call` y `src/evaluator.zig` despachan métodos de Date
  por `@@type`.

## Verificación

```bash
diff <(./zig-out/bin/lou run tests/compat/date-object.lou) \
     <(node tests/compat/date-object.js)
# sin diferencias
```

Test unitario en `src/evaluator.zig`: `Date objects coerce to timestamps in
arithmetic` (`new Date(1000) - new Date(500) === 500`).

## Limitaciones

- La zona horaria local es UTC (offset 0): los getters/setters locales no
  reflejan el TZ del sistema.
- `toString()` no incluye el nombre de la zona (`GMT+0000 (...)`), por eso el
  fixture solo comprueba que sea no vacío.
- Formatos de fecha no ISO (`"Jan 15, 2024"`) no se parsean.

## Referencias

- `src/builtins/date/{constructor,methods,static,date_utils}.zig`
- `src/coercion.zig` (`dateTimestamp`)
- `tests/compat/date-object.{js,lou}`
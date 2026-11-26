# RegExp Properties (`/regex/.source`, `.flags`, `.lastIndex`)

## status

**pendiente** — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SKIP)

`tests/compat/regex-properties.lou` sigue FAIL. Primera divergencia (línea 1), Lou vs Node:

```text
Lou : undefined
Node: hello
```

Los getters `source`/`flags`/`global`/... de una instancia RegExp devuelven `undefined`. El archivo estaba en `hechos/` pese a declarar FAIL.

```bash
diff <(./zig-out/bin/lou run tests/compat/regex-properties.lou) <(node tests/compat/regex-properties.js)
```

## Problema
`tests/compat/regex-properties.lou` falla. Output actual (Lou) emite `undefined` para
todas las propiedades RegExp consultadas; node produce los valores esperados.

## Contexto
ES2020 define en instancias de RegExp:
- `source` — el patrón fuente (string)
- `flags` — concatenación ordenada de flags activos (`"gi"`, `"gimsuy"`, etc.)
- `global`, `ignoreCase`, `multiline`, `unicode`, `sticky` — booleanos individuales
- `lastIndex` — índice mutable, inicialmente 0

El compat test cubre las 3 instancias RegExp, todos los getters de flag, y la
mutabilidad de `lastIndex`.

## Baseline (qué existe ya)
- `new RegExp(pattern, flags)` — constructor soportado en `src/builtins/regexp/...`
- Acceso a propiedades via `.get_prop` opcode en `src/vm.zig` — pero las propiedades
  RegExp no retornan los getter-result esperados, emiten `undefined`

## Código que falla (Lou)
```js
const r = /hello/gi;
console.log(r.source);    // esperado: hello
console.log(r.flags);     // esperado: gi
```

## Tests
- Unit: revisar que instancias de RegExp devuelven `source`/`flags`/booleanos en `.get_*`
- Compat: `tests/compat/regex-properties.lou` debe pasar vs `node tests/compat/regex-properties.js`

## Verificación
```bash
diff <(./zig-out/bin/lou run tests/compat/regex-properties.lou 2>&1) \
     <(node tests/compat/regex-properties.js 2>&1)
```

## pendiente
- Implementar los getters de RegExp en el dispatch de get_prop (vm.zig) y/o en la
  capa builtin regexp para que devuelvan `source`/`flags`/booleanos reales.
- Implementar mutabilidad de `lastIndex` via `set_prop` en RegExp instances.


- **Estimated fix effort**: 2h: implement RegExp getters in src/builtins/regexp (source, flags, individual flag booleans) and ensure lastIndex is mutable via set_prop.

## Estado del test (auto 2026-06-22)

- Compat test match: `regex-properties.lou` (EXACT)
- Test status: `FAIL`
- Diff excerpt: 19 lines `undefined` vs node expecting `hello`, `gi`, etc.

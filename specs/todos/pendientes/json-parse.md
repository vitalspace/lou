# JSON.parse

## status

**pendiente** — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SKIP)

`tests/compat/json-parse.lou` sigue FAIL. Primera divergencia (línea 17), Lou vs Node:

```text
Lou : FAIL(\x): no throw
Node: ok(\x): true / SyntaxError
```

`JSON.parse` no lanza `SyntaxError` con escapes inválidos (\x, \v, \u truncados). El archivo estaba en `hechos/` pese a declarar `pendiente`.

```bash
diff <(./zig-out/bin/lou run tests/compat/json-parse.lou) <(node tests/compat/json-parse.js)
```


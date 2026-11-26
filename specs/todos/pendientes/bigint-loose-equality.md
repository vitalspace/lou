# BigInt — Loose equality (==) con coerción

## status

**pendiente** — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SKIP)

`tests/compat/bigint-loose-eq.lou` sigue FAIL. Primera divergencia (línea 13), Lou vs Node:

```text
Lou : false
Node: true
```

Falla la coerción Booleano→Número→BigInt dentro de `==` (p. ej. `1n == true`). El archivo estaba en `hechos/` pese a declarar `pendiente`.

```bash
diff <(./zig-out/bin/lou run tests/compat/bigint-loose-eq.lou) <(node tests/compat/bigint-loose-eq.js)
```


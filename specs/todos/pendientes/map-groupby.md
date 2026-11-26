# Map.groupBy y Object.groupBy

## status

**pendiente** — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SKIP)

`tests/compat/map-groupby.lou` sigue FAIL. Primera divergencia (línea 19), Lou vs Node:

```text
Lou : ---Throw did not propagate---
Node: ---Throw propagated---
```

Una excepción lanzada dentro del callback de `Map.groupBy` no se propaga. El archivo estaba en `hechos/` pese a declarar `pendiente`.

```bash
diff <(./zig-out/bin/lou run tests/compat/map-groupby.lou) <(node tests/compat/map-groupby.js)
```


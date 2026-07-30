# Collections (Array, Map, Set) — Baseline

## status
completado

## Problema
`tests/compat/collections.lou` verifica que las operaciones básicas de colecciones funcionan correctamente. Es un test de baseline que cubre Array, Map y Set.

## Contexto
El test comprueba:

**Array:**
- `length`, `push(7)`, `pop()`
- `indexOf(4)`, `includes(5)`
- `slice(2, 5)`, `reverse()`, `join(",")`
- `Array.from("abc")`, `Array.isArray([1, 2, 3])`

**Map:**
- `new Map()`, `.set("a", 1)`, `.set("b", 2)`
- `.get("a")`, `.has("b")`, `.size`

**Set:**
- `new Set([1, 2, 3, 2, 1])` — deduplicación automática
- `.size`, `.has(2)`

## Verificación
```bash
./zig-out/bin/lou run tests/compat/collections.lou
diff <(./zig-out/bin/lou run tests/compat/collections.lou 2>&1) \
     <(node tests/compat/collections.js 2>&1)
```

## Estado del test
- Compat test match: `collections.lou`
- Test status: **PASS**

## pendiente
- (ninguno — baseline test, todas las operaciones funcionan)

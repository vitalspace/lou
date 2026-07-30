# Logical Operator Edge Cases (`||`, `&&`, `??`) — Short-Circuit

## status
completado

## Problema
`tests/compat/bigint-logical-edge.lou` verifica que los operadores lógicos (`||`, `&&`, `??`) evalúan correctamente con short-circuit y efectos laterales. A pesar del nombre del test (que menciona "bigint"), el test no usa valores BigInt — verifica el comportamiento general de short-circuit de los operadores lógicos.

## Contexto
El test comprueba el comportamiento de short-circuit con asignaciones como efecto lateral:

**`||` (OR):**
- `true || (sideEffect = true)` → el lado derecho NO se ejecuta → `sideEffect` sigue `false`
- `false || (sideEffect = true) || "default"` → el lado derecho SÍ se ejecuta → `sideEffect = true`

**`&&` (AND):**
- `true && (sideEffect = true)` → el lado derecho SÍ se ejecuta → `sideEffect = true`
- `false && (sideEffect = true)` → el lado derecho NO se ejecuta → `sideEffect` sigue `false`

**`??` (Nullish coalescing):**
- `(sideEffect = true) ?? "default"` → la asignación se ejecuta primero → `sideEffect = true`
- `null ?? (sideEffect = true)` → el lado izquierdo es nullish → se ejecuta el derecho → `sideEffect = true`

## Verificación
```bash
./zig-out/bin/lou run tests/compat/bigint-logical-edge.lou
diff <(./zig-out/bin/lou run tests/compat/bigint-logical-edge.lou 2>&1) \
     <(node tests/compat/bigint-logical-edge.js 2>&1)
```

## Estado del test
- Compat test match: `bigint-logical-edge.lou`
- Test status: **PASS**

## pendiente
- (ninguno — test de regresión, operadores lógicos con short-circuit ya implementados)

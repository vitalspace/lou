# Arrow Function Syntax

## status
completado

## Problema
`tests/compat/arrow-syntax.lou` verifica que la sintaxis de arrow functions funciona correctamente en todos sus formatos: expresión simple, cuerpo de bloque, sin parámetros, múltiples parámetros, rest parameters, y uso como callbacks.

## Contexto
El test comprueba:

**Expresiones básicas:**
- `(a, b) => a + b` — múltiples parámetros, expresión simple
- `() => 42` — sin parámetros
- `x => x * 2` — un solo parámetro sin paréntesis

**Cuerpo de bloque:**
- `const fact = (n) => { if (n <= 1) return 1; return n * fact(n - 1); }` — recursión con arrow function

**Callbacks:**
- `[1, 2, 3].map(x => x * 2)` → `[2, 4, 6]`
- `[1, 2, 3, 4].filter(x => x % 2 === 0)` → `[2, 4]`

**Rest parameters:**
- `(...args) => args[0]` — head function
- `(...args) => args` — identity
- `(a, b, ...rest) => rest` — rest después de params posicionales

## Verificación
```bash
./zig-out/bin/lou run tests/compat/arrow-syntax.lou
diff <(./zig-out/bin/lou run tests/compat/arrow-syntax.lou 2>&1) \
     <(node tests/compat/arrow-syntax.js 2>&1)
```

## Estado del test
- Compat test match: `arrow-syntax.lou`
- Test status: **PASS**

## pendiente
- (ninguno — test de regresión, arrow functions ya implementadas)

# Lexer: Exponential Notation (`1e10`, `3.14e-2`, `2.5E+3`)

## status
completado

## Problema
`tests/compat/exponential-notation.lou` verifica que el lexer parsea correctamente literales numéricos en notación exponencial (científica), tanto con `e` minúscula como con `E` mayúscula, y con exponentes positivos y negativos.

## Contexto
El test comprueba:

**Literales:**
- `1e10` → `10000000000`
- `3.14e-2` → `0.0314`
- `2.5E+3` → `2500`
- `1E-5` → `0.00001`
- `1.5e4` → `15000`
- `99E0` → `99`

**Operaciones aritméticas con notación exponencial:**
- `1e10 + 1e-10` → `10000000000.0000000001` (approx)
- `3.14e2 / 2e1` → `15.7`

## Verificación
```bash
./zig-out/bin/lou run tests/compat/exponential-notation.lou
diff <(./zig-out/bin/lou run tests/compat/exponential-notation.lou 2>&1) \
     <(node tests/compat/exponential-notation.js 2>&1)
```

## Estado del test
- Compat test match: `exponential-notation.lou`
- Test status: **PASS**

## pendiente
- (ninguno — test de regresión, el lexer ya soporta notación exponencial)

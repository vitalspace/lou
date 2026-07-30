# Lexer: Leading-Dot Float Literals (`.5`, `.125`)

## status
completado

## Problema
`tests/compat/leading-dot-float.lou` verifica que el lexer parsea correctamente literales de punto flotante que comienzan con `.` (sin dígito inicial), una sintaxis válida en JavaScript.

## Contexto
El test comprueba:

**Literales:**
- `.5` → `0.5`
- `.125` → `0.125`
- `.001` → `0.001`

**Operaciones aritméticas:**
- `.5 + .5` → `1`
- `.5 * .5` → `0.25`
- `.1 + .2` → `0.30000000000000004` (precisión IEEE 754)

**Notación exponencial con leading dot:**
- `.5e2` → `50`
- `.125e-1` → `0.0125`

## Verificación
```bash
./zig-out/bin/lou run tests/compat/leading-dot-float.lou
diff <(./zig-out/bin/lou run tests/compat/leading-dot-float.lou 2>&1) \
     <(node tests/compat/leading-dot-float.js 2>&1)
```

## Estado del test
- Compat test match: `leading-dot-float.lou`
- Test status: **PASS**

## pendiente
- (ninguno — test de regresión, el lexer ya soporta leading-dot floats)

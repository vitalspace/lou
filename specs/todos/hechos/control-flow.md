# Control Flow — Baseline

## status
completado

## Problema
`tests/compat/control.lou` verifica que las estructuras de control de flujo básicas funcionan correctamente. Es un test de baseline que cubre bucles, condicionales, y funciones.

## Contexto
El test comprueba:

**For Loop:**
- Suma de enteros de 1 a 5 → `total = 15`
- `console.log(total)`

**While Loop:**
- Factorial de 5 → `fact = 120`
- `console.log(fact)`

**If/Else:**
- `x = 10` → `x > 5` → imprime `"big"`

**Funciones:**
- `function greet(name) { return "Hello, " + name; }`
- `greet("World")` → `"Hello, World"`

**Recursión:**
- Fibonacci recursivo: `fib(10)` → `55`

## Verificación
```bash
./zig-out/bin/lou run tests/compat/control.lou
diff <(./zig-out/bin/lou run tests/compat/control.lou 2>&1) \
     <(node tests/compat/control.js 2>&1)
```

## Estado del test
- Compat test match: `control.lou`
- Test status: **PASS**

## pendiente
- (ninguno — baseline test, todas las operaciones funcionan)

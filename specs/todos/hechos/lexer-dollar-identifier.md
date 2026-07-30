# Lexer: Dollar Sign in Identifiers (`$`)

## status
completado

## Problema
`tests/compat/dollar-identifier.lou` verifica que el lexer soporta `$` como parte de identificadores, cumpliendo con ECMAScript (donde `$` y `_` son los únicos caracteres no-alfanuméricos permitidos en nombres de variable).

## Contexto
El test comprueba:

**Variables:**
- `$x = 42`, `$$ = "double"`, `$0 = "zero"`, `$_ = "underscore"`
- `console.log($x, $$, $0, $_)` → `42 double zero underscore`

**Arrays:**
- `$arr = [1, 2, 3]`
- `console.log($arr[0])` → `1`

**Parámetros de función:**
- `($n) => $n * 2`
- `console.log(double(5))` → `10`

**Propiedades de objeto:**
- `obj = { $prop: "value" }`
- `console.log(obj.$prop)` → `"value"`

## Verificación
```bash
./zig-out/bin/lou run tests/compat/dollar-identifier.lou
diff <(./zig-out/bin/lou run tests/compat/dollar-identifier.lou 2>&1) \
     <(node tests/compat/dollar-identifier.js 2>&1)
```

## Estado del test
- Compat test match: `dollar-identifier.lou`
- Test status: **PASS**

## pendiente
- (ninguno — test de regresión, el lexer ya soporta `$` en identificadores)

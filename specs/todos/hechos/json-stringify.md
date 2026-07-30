# JSON.stringify

## status
completado

## Problema
`tests/compat/json-stringify.lou` verifica que `JSON.stringify()` funciona correctamente con todos los tipos primitivos, objetos, arrays, replacers (tanto funciones como arrays whitelist), y el parámetro `space`.

## Contexto
El test comprueba:

**Tipos básicos:**
- `string`, `number`, `boolean`, `null`
- Objetos planos y arrays

**Function replacer:**
- Transformación de números (`doubleNumbers`)
- Exclusión de claves (`excludeB`)
- Procesamiento de objetos anidados (`nestedReplacer`)
- Transformación de elementos de array
- Verificación de claves correctas para arrays

**Array (whitelist) replacer:**
- Whitelisting de propiedades
- Objetos anidados con whitelist
- Claves numéricas y strings

**Parámetro `space`:**
- Formateo con indentación

## Verificación
```bash
./zig-out/bin/lou run tests/compat/json-stringify.lou
diff <(./zig-out/bin/lou run tests/compat/json-stringify.lou 2>&1) \
     <(node tests/compat/json-stringify.js 2>&1)
```

## Estado del test
- Compat test match: `json-stringify.lou`
- Test status: **PASS**

## pendiente
- (ninguno — test de regresión, JSON.stringify ya implementado)

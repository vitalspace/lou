# Object Basics — Baseline

## status
completado

## Problema
`tests/compat/objects.lou` verifica que las operaciones básicas con objetos funcionan correctamente. Es un test de baseline que cubre creación, acceso, mutación y anidamiento.

## Contexto
El test comprueba:

**Objeto plano:**
- `const person = { name: "Ada", age: 36 }`
- `console.log(person.name)` → `"Ada"`
- `console.log(person.age)` → `36`
- Mutación: `person.age = 37` → `console.log(person.age)` → `37`

**Objetos anidados:**
- `const data = { user: { id: 1, tags: ["admin", "active"] } }`
- `console.log(data.user.id)` → `1`
- `console.log(data.user.tags)` → `["admin", "active"]`

## Verificación
```bash
./zig-out/bin/lou run tests/compat/objects.lou
diff <(./zig-out/bin/lou run tests/compat/objects.lou 2>&1) \
     <(node tests/compat/objects.js 2>&1)
```

## Estado del test
- Compat test match: `objects.lou`
- Test status: **PASS**

## pendiente
- (ninguno — baseline test, todas las operaciones funcionan)

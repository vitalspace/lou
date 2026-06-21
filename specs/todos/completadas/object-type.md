# Implementación del tipo Object

**Prioridad: alta**
**Estado: COMPLETADO**

## Problema

Lou no tiene implementación del tipo `Object` global. Métodos como `Object.keys()`, `Object.values()`, `Object.assign()`, etc. no existen.

## Contexto

- Spec existente en `specs/objects/objects.md` (324 líneas con diseño detallado)
- El objeto `Object` es fundamental: casi todo en JS es un Object
- Implementar el constructor `Object()` y métodos estáticos
- Property descriptors, prototype chain, etc.

## Implementación

### Archivos creados:
- `src/builtins/object/object.zig` - Registro del objeto builtin
- `src/builtins/object/keys.zig` - Object.keys()
- `src/builtins/object/assign.zig` - Object.assign()
- `src/builtins/object/entries.zig` - Object.entries()
- `src/builtins/object/values.zig` - Object.values()
- `src/builtins/object/hasOwn.zig` - Object.hasOwn()
- `src/builtins/object/create.zig` - Object.create()

### Archivos modificados:
- `src/builtins/builtinObjects.zig` - agregado OBJECT_OBJECT

## Referencia

- `specs/objects/objects.md`

## Verificación

### Código JavaScript a verificar

```js
// Object.keys
console.log(Object.keys({a:1, b:2}));  // ["a", "b"]

// Object.assign
console.log(Object.assign({}, {a:1}, {b:2}));  // {a:1, b:2}

// Object.create (si es soportado)
const obj = Object.create(null);
console.log(obj);  // {} sin prototipo

// Object.entries
console.log(Object.entries({a:1, b:2}));  // [["a",1],["b",2]]

// Object.values
console.log(Object.values({a:1, b:2}));  // [1,2]

// Object.hasOwn (o hasOwnProperty)
console.log(Object.hasOwn({a:1}, "a"));  // true
console.log(Object.hasOwn({a:1}, "b"));  // false
```

### Resultado
Todos los tests pasan y la salida coincide con Node.js.

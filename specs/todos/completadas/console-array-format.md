# Formateo de arrays largos en console.log

**Prioridad: baja**

**Estado: COMPLETADO**

## Problema

Node.js formatea arrays largos en `console.log` con saltos de línea para mejorar legibilidad, mientras lou imprime todo en una sola línea.

Node.js:
```
[ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ]
[ 1, 2, 3, 4,
  5, 6, 7, 8,
  9, 10 ]
```

Lou (después):
```
[ 1, 2, 3 ]
[ 1, 2, 3, 4, 5, 6, 
  7, 8, 9, 10, 11, 12, 
  13, 14, 15 ]
[]
[ [ 1, 2 ], [ 3, 4 ], [ 5, 6 ], [ 7, 8 ], [ 9, 10 ] ]
```

## Contexto

- Node.js usa ~80 caracteres como ancho máximo antes de hacer wrap
- Afecta `src/builtins/console/log.zig` y `error.zig`
- No afecta comportamiento, solo presentación

## Implementación

- Agregada función `shouldFormatArrayWrapped` para determinar si el array excede el ancho máximo
- Agregada función `valueDisplayWidth` para estimar el ancho visual de cada valor
- Agregada función `printArrayWrapped` para imprimir arrays con salto de línea cada 6 elementos
- Modificada `Log` y `Error` para usar el nuevo formateo
- Arrays con ≤10 elementos se imprimen en una línea
- Arrays grandes se envuelven cada 6 elementos con indentación de 2 espacios

## Verificación

### Código JavaScript a verificar

```js
// Array corto (debe imprimir en una línea)
console.log([1, 2, 3]);              // esperado: [ 1, 2, 3 ]

// Array largo (debe hacer wrap después de ~80 chars, como Node.js)
console.log([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]);

// Array vacío
console.log([]);

// Array anidado
console.log([[1,2], [3,4], [5,6], [7,8], [9,10]]);
```

### Cómo correr y verificar

1. **Archivo de prueba**: `js/test-console-array.js`

2. **Ejecutar con Lou (Zig)**:
```bash
zig build run -- run js/test-console-array.js
```

3. **Comparar con Node.js**:
```bash
node js/test-console-array.js
```

4. **Tests**: `zig build test`
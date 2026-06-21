# Object literal con keys numéricas

**Prioridad: baja**

**Estado: COMPLETADO**


## Problema

El parser no acepta números como property keys en object literals:

```js
// Esto falla con ExpectedPropertyName
var obj = { 0: 'a', 1: 'b', length: 2 };
```

## Contexto

- `Array.from()` con array-like objects requiere esta sintaxis
- Solo acepta `.String` e `.Identifier` como keys

## Referencia

- `src/parser.zig:520-522`

## Solución propuesta

Agregar `.Integer` (y `.Float`) al switch en `parseObjectLiteral`, convertir el número a string para usarlo como key:

```zig
const key = switch (this.current_token.type) {
    .String => this.current_token.literal,
    .Identifier => this.current_token.literal,
    .Integer => ...  // convertir número a string
    .Float => ...    // convertir float a string
    else => return error.ExpectedPropertyName,
};
```

## Verificación

### Código JavaScript a verificar

```js
// numeric keys en object literal
console.log({ 0: 'a', 1: 'b' });  // { '0': 'a', '1': 'b' }

// acceso por índice numérico
const obj = { 0: 'x', 1: 'y'};
console.log(obj[0]);  // 'x'

// Array.from con array-like
const arrayLike = { 0: 'a', 1: 'b', length: 2 };
console.log(Array.from(arrayLike));  // ['a', 'b'] (si thisArg está soportado)
```

### Cómo correr y verificar

1. **Archivo de prueba**: `js/test-numeric-keys.js`

2. **Ejecutar con Lou (Zig)**:
```bash
zig build run -- run js/test-numeric-keys.js
```

3. **Verificar que no hay `ExpectedPropertyName` error

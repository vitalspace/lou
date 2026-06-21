# Console.log colores ANSI

**Prioridad: media**

## Problema

`console.log` usa colores ANSI por defecto. Los strings se imprimen en verde (`\x1b[32m`), lo cual es diferente a Node.js que imprime sin color.

## Contexto

- `src/builtins/console/log.zig` contiene la lógica de colores ANSI
- Las secuencias de escape son: `\x1b[32m` (verde) y `\x1b[0m` (reset)
- El archivo `src/utils/ansi.zig` define las constantes de colores

## Verificación

```bash
# Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/main.js 2>&1 | od -c
node js/main.js 2>&1 | od -c
```

## Casos prueba

1. String imprimido: `console.log("hello")` → debe contener secuencias ANSI verdes
2. Sin soporte ANSI: desconectar stdout → sin códigos de color
3. Verificar que el color verde es `#008000` (o similar)
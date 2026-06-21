# Consola ANSI y colores ✅

~~**Prioridad: baja**~~ **Resuelto**

## Problema

`console.log` en lou imprime texto plano sin colores. Node.js colorea tipos: números en amarillo, strings en verde, objetos con sintaxis resaltada, errores en rojo, etc.

## Contexto

- Es puramente cosmético pero mejora DX
- Ya hay un spec `specs/console/log and ansi.md` que describe la idea
- Implementar en `@ansi.zig` y luego integrar en `@log.zig`
- Tener cuidado: cuando la salida no es una TTY, no imprimir ANSI escapes

## Implementación

- `src/utils/ansi.zig`: nueva función `supportsAnsi(io)` que detecta TTY vía `Io.File.supportsAnsiEscapeCodes`
- `src/builtins/console/log.zig`: `printValueTo` acepta `use_ansi`, strings en verde (sin comillas)
- `src/builtins/console/error.zig`: mismo tratamiento, `[ERROR]` en rojo, strings en verde

## Referencia

- `specs/console/log and ansi.md`

## Verificación

- `console.log(42)` imprime `42` en amarillo (en terminal ✅)
- `console.log("hola")` imprime `hola` en verde ✅
- No emite escapes ANSI cuando se redirige a un archivo ✅

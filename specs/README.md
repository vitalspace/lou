# Especificaciones de Paridad Regex — Lou

Este directorio contiene las especificaciones y el roadmap para alcanzar
paridad con el motor de expresiones regulares de JavaScript/Node.js en Lou.

## Estructura

| Archivo | Descripción |
|---------|-------------|
| `README.md` | Esta visión general |
| `01-regex-engine.md` | Motor interno: parser, compilador, VM |
| `02-regexp-builtins.md` | Constructor `RegExp`, prototipo, propiedades |
| `03-string-methods.md` | Métodos de string que interactúan con regex |
| `04-edge-cases-and-bugs.md` | Casos borde, incompatibilidades conocidas, bugs |
| `TODO.md` | Lista consolidada priorizada de tareas |

## Estado actual

El motor regex de Lou está en una etapa temprana pero funcional.
Actualmente soporta:

- ✅ Literales regex (`/pattern/flags`)
- ✅ Constructor `RegExp(pattern, flags)`
- ✅ `test()`, `exec()` básicos
- ✅ Global (`g`), case-insensitive (`i`), multiline (`m`)
- ✅ DotAll (`s`), sticky (`y`), unicode (`u`)
- ✅ Grupos de captura (numerados y nombrados)
- ✅ Grupos no capturadores (`(?:...)`)
- ✅ Lookahead positivo/negativo (`(?=...)`, `(?!...)`)
- ✅ Lookbehind positivo/negativo (`(?<=...)`, `(?<!...)`) — **experimental**
- ✅ Backreferences (`\1`, `\2`, ...)
- ✅ Clases de caracteres (`[...]`, `[^...]`)
- ✅ Escape shorthand classes (`\d`, `\w`, `\s` y sus inversos)
- ✅ Unicode escapes (`\uXXXX`, `\u{XXXXX}`)
- ✅ Hex escapes (`\xHH`) dentro de regex
- ✅ Control escapes (`\cX`) dentro de regex
- ✅ Quantificadores (`*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}`) greedy y lazy
- ✅ Propiedades `.source`, `.flags`, `.global`, `.ignoreCase`, `.multiline`, `.dotAll`, `.unicode`, `.sticky`
- ✅ `lastIndex` con `/g` y `/y`
- ✅ Alternancia (`|`)

## Objetivo

Alcanzar paridad completa con la especificación ECMAScript para RegExp,
incluyendo el comportamiento del prototype, los métodos de `String`
y todos los casos borde definidos en el estándar.

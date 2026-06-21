# TODO — RegExp Parity (Lou ↔ JavaScript/Node.js)

## Convenciones

- 🔴 **P1 — Critical**: Bloqueante, bugs, missing core functionality
- 🟡 **P2 — High**: Importante para paridad, pero con workaround
- 🔵 **P3 — Medium**: Feature completo, tests existentes parcialmente
- ⚪ **P4 — Low**: Nice-to-have, edge cases poco comunes

---

## Fase 1 — Estabilización (P1-P2)

### P1 — Bugs del engine

- [ ] **[B1] \B word boundary edge case** — `specs/04-edge-cases.md:B1`
      Hacer que `\B` coincida en todas las posiciones entre word chars.
      Afecta: `"hello".match(/\B/g)` → debe retornar 4 matches.

- [ ] **[B2] Captures en lookahead** — `specs/04-edge-cases.md:B2`
      Preservar capturas dentro de lookahead assertions.
      Afecta: `/(?=(a))\1/.test("a")` → debe ser true.

- [ ] **[B3] RegExp constructor hereda flags** — `specs/02-regexp-builtins.md:B3`
      `new RegExp(/foo/gi)` debe heredar flags del regexp original.
      Archivo: `src/builtins/regex/regexp_constructor.zig`

### P2 — Propiedades y métodos faltantes

- [ ] **`RegExp.prototype.hasIndices`** — `specs/02-regexp-builtins.md`
      Exponer la propiedad `hasIndices` (d flag) desde el MemberAccess handler.
      Ya existe en `RegExpValue.has_indices`.

- [ ] **`RegExp.prototype.toString()`** — `specs/02-regexp-builtins.md`
      Implementar `/regex/[flags].toString()` → `"/regex/flags"`.
      Se puede implementar como:
      ```js
      RegExp.prototype.toString = function() { return "/" + this.source + "/" + this.flags; }
      ```
      O en el `MemberAccess` handler del evaluador.

- [ ] **Orden canónico de flags** — `specs/02-regexp-builtins.md`
      Asegurar que `.flags` retorne en orden `"dgimsuy"` según ES2023.

- [ ] **matchAll incluye capturas** — `specs/03-string-methods.md`
      Los arrays individuales en el iterador de matchAll deben incluir
      grupos capturados y named captures.

- [ ] **matchAll requiere /g** — `specs/03-string-methods.md`
      Lanzar TypeError si el regexp no tiene flag `g`.

- [ ] **replace con callback** — `specs/03-string-methods.md`
      Aceptar function como segundo argumento:
      ```js
      "hello".replace(/l/g, (m, offset, str) => m.toUpperCase())
      ```

---

## Fase 2 — Paridad básica (P2-P3)

### Named backreferences

- [ ] **`\k<name>` en el parser** — `specs/01-regex-engine.md`
      Añadir soporte para `\k<name>` en `parseEscape()` del parser.
      Buscar el nombre en `named_groups` y emitir un `backref` node
      con el índice correspondiente.

### String escapes en el lexer de Lou

- [ ] **`\xHH` en strings JS** — `specs/04-edge-cases.md:L1`
      El lexer de Lou debe interpretar `\xHH` como el byte hex
      correspondiente (no como literal).

- [ ] **`\uHHHH` en strings JS** — `specs/04-edge-cases.md:L2`
      El lexer de Lou debe interpretar `\uHHHH` como el codepoint
      Unicode correspondiente.

- [ ] **Template strings escapes** — `specs/04-edge-cases.md:L3`
      Soportar `\r`, `\f`, `\v` en template strings.

### Unicode property escapes

- [ ] **`\p{...}` en parser** — `specs/01-regex-engine.md`
      Implementar:
      - `\p{L}` (letter), `\p{N}` (number), `\p{P}` (punctuation)
      - `\p{ASCII}`, `\p{Alphabetic}`, `\p{Uppercase}`, `\p{Lowercase}`
      - `\P{...}` negación
      - Versión simplificada: tabla de categorías Unicode para BMP

---

## Fase 3 — Paridad completa (P3-P4)

### Symbol methods

- [ ] **`RegExp.prototype[Symbol.match]`**
- [ ] **`RegExp.prototype[Symbol.replace]`**
- [ ] **`RegExp.prototype[Symbol.search]`**
- [ ] **`RegExp.prototype[Symbol.split]`**

Estos métodos son usados internamente por `String.prototype.match`,
`replace`, `search`, `split`. Actualmente Lou llama directamente a
las funciones de `RegexpBuiltin`. Para paridad, debería:

1. Verificar si el argumento regexp tiene `Symbol.match/replace/...`
2. Si existe, invocar ese método
3. Si no existe (string literal), usar la lógica actual

### d (hasIndices) flag completo

- [ ] **indices en RegExp.prototype.exec**
- [ ] **indices.groups para named captures**
- [ ] **Propagación a matchAll y replace**

El engine ya genera los datos de índices cuando `has_indices` es true.
Falta exponerlos correctamente en `RegExp.prototype.exec` y en las
string methods correspondientes.

### Static RegExp properties

- [ ] **`RegExp.$1`..`$9`** — Últimas capturas
      Requiere almacenar las últimas capturas en el entorno global.

- [ ] **`RegExp.lastMatch`** — `$&`
- [ ] **`RegExp.lastParen`** — `$+`
- [ ] **`RegExp.leftContext`** — `` $` ``
- [ ] **`RegExp.rightContext`** — `$'`
- [ ] **`RegExp.input`** — `$_`

### Inline flags

- [ ] **`(?i)`** — Ignore case mode
- [ ] **`(?-i)`** — Case sensitive mode
- [ ] **`(?m)`**, `(?-m)` — Multiline on/off
- [ ] **`(?s)`**, `(?-s)` — DotAll on/off

Influencia limitada: las flags inline cambian el comportamiento para
secciones del patrón. Requiere modificar la VM para aceptar flags
dinámicos durante la ejecución.

---

## Fase 4 — Optimización y testing

### Performance

- [ ] **Lookbehind optimizado** — Limitar búsqueda a atrás en lugar de
      probar desde posición 0. Se puede calcular la longitud máxima del
      patrón de lookbehind analizando el AST.

- [ ] **Cache LRU de patrones compilados** — Actualmente el cache es por
      objeto `RegExpValue`. Un cache global con política LRU beneficiaría
      a aplicaciones que crean muchos regexps temporales.

- [ ] **Compilación lazy diferida** — No compilar el regexp hasta el
      primer `exec`/`test`. Ya implementado parcialmente (campo `cached`).

### Testing

- [ ] **Suite 08: Captures avanzadas** — Captures anidadas, opcionales,
      lookahead con captures, named backrefs `\k<name>`.

- [ ] **Suite 09: Sticky flag** — `/y` solo, `/y` con `/g`,
      `lastIndex` en sticky, edge cases.

- [ ] **Suite 10: replace avanzado** — Callback replacement,
      `$<name>` named captures, edge cases con `$`` y `$'`.

- [ ] **Suite 11: Unicode** — `\p{L}`, `\p{N}`, caracteres multi-byte,
      unicode en clases, case folding unicode con `/ui`.

- [ ] **Suite 12: Flags combinados** — `gmi`, `gms`, `gsy`, `ud`,
      interacciones de flags.

- [ ] **Suite 13: Performance** — Patrones largos, backtracking profundo,
      lookbehind con cadenas largas, step limit.

- [ ] **Suite 14: Edge cases del engine** — Cuantificadores anidados,
      backrefs a grupos que no participaron, grupos vacíos,
      alternancia vacía `(|)`, cuantificadores en grupos vacíos.

### Infraestructura

- [ ] **README.md en test/** — Documentar cómo añadir suites, formato,
      convenciones, limitaciones de Lou.

- [ ] **Gitignore para run_all.js** — O no incluir el archivo generado
      en el repo, o añadir `.gitignore` si se genera en build.

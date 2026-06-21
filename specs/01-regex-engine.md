# 01 — Motor RegExp (Engine)

## Ubicación del código

| Componente | Ruta |
|------------|------|
| AST del engine | `src/builtins/regex/engine/ast.zig` |
| Parser | `src/builtins/regex/engine/parser.zig` |
| Compilador | `src/builtins/regex/engine/compiler.zig` |
| VM | `src/builtins/regex/engine/vm.zig` |
| Wrapper | `src/builtins/regex/regex.zig` |
| API builtin | `src/builtins/regex/regexp.zig` |
| Constructor | `src/builtins/regex/regexp_constructor.zig` |
| Runtime | `src/types/runtime.zig` (RegExpValue) |

## AST (ast.zig)

### NodeTypes soportados

| NodeType | Descripción |
|----------|-------------|
| `empty` | Nodo vacío |
| `literal` | Carácter literal (codepoint u21) |
| `dot` | `.` (cualquier carácter excepto newline) |
| `char_class` | Clase de caracteres `[...]` o `[^...]` |
| `anchor_bol` | `^` (inicio de línea) |
| `anchor_eol` | `$` (fin de línea) |
| `word_boundary` | `\b` o `\B` |
| `concat` | Concatenación de hijos |
| `alternate` | Alternancia `\|` |
| `repeat` | Cuantificador `*`, `+`, `?`, `{n,m}` |
| `capture` | Grupo de captura `(...)` |
| `non_capture` | Grupo no capturador `(?:...)` |
| `backref` | Retroreferencia `\1`..`\9` |
| `lookahead` | Lookahead `(?=...)` o `(?!...)` |
| `lookbehind` | Lookbehind `(?<=...)` o `(?<!...)` |

### NodeTypes NO implementados (necesarios para paridad)

| NodeType | Descripción | Prioridad |
|----------|-------------|-----------|
| `atomic` | Grupo atómico `(?>...)` | Baja |
| `subroutine` | Llamada a subrutina `(?R)`, `(?1)` | Baja |
| `conditional` | Patrón condicional `(?(cond)yes|no)` | Baja |
| `inline_flags` | Cambio de flags inline `(?i)`, `(?-i)` | Media |

## Parser (parser.zig)

### Escape sequences soportados

| Escape | Soporte |
|--------|---------|
| `\d`, `\D` | ✅ Clase dígitos |
| `\w`, `\W` | ✅ Clase word |
| `\s`, `\S` | ✅ Clase whitespace |
| `\b`, `\B` | ✅ Word boundary |
| `\t`, `\n`, `\r`, `\f`, `\v` | ✅ Control escapes |
| `\0` | ✅ Null character |
| `\xHH` | ✅ Hex escape en el patrón regex |
| `\uHHHH` | ✅ Unicode escape (BMP) |
| `\u{H...}` | ✅ Unicode escape extendido |
| `\cX` | ✅ Control escape (dentro del patrón regex) |
| `\k<name>` | ❌ Named backreference |
| `\p{...}`, `\P{...}` | ❌ Unicode property escapes |

### Group types soportados

| Sintaxis | Tipo | Soporte |
|----------|------|---------|
| `(...)` | Capture | ✅ |
| `(?:...)` | Non-capture | ✅ |
| `(?=...)` | Positive lookahead | ✅ |
| `(?!...)` | Negative lookahead | ✅ |
| `(?<=...)` | Positive lookbehind | ✅ |
| `(?<!...)` | Negative lookbehind | ✅ |
| `(?<name>...)` | Named capture | ✅ |
| `(?>...)` | Atomic group | ❌ |
| `(?i:...)` | Inline flags | ❌ |

### Limitaciones del parser

1. **`//` se confunde con comentario**: El lexer de Lou interpreta `//` como
   inicio de comentario de línea. Usar `new RegExp("")` como workaround.

2. **Clases con rangos negados**: `[^...]` funciona, pero `[^...]` dentro de
   lookbehinds puede fallar.

3. **Capturing inside lookahead**: Lou no preserva captures dentro de
   lookahead assertions (bug conocido).

## Compilador (compiler.zig)

### Opcodes

| Opcode | Descripción |
|--------|-------------|
| `match` | Match exitoso |
| `fail` | Fallo inmediato |
| `char` | Coincidir carácter |
| `any` | Coincidir cualquier char (excepto newline sin `/s`) |
| `class` | Coincidir clase de caracteres |
| `jmp` | Salto incondicional |
| `split` | Bifurcación (NFA threading) |
| `save` | Guardar posición (capturas) |
| `assert_bol` | Assert inicio de línea |
| `assert_eol` | Assert fin de línea |
| `assert_wb` | Assert word boundary |
| `look_start` | Inicio de lookaround |
| `look_end` | Fin de lookaround |
| `backref` | Retroreferencia |

### Limitaciones del compilador

1. **No hay límite de pasos**: La VM tiene un límite de 1M pasos pero no se
   expone al usuario ni es configurable.

2. **Compilación repetida**: Cada `exec`/`test` re-compila si no hay cache.
   El cache es por objeto `RegExpValue`, no global.

3. **No hay optimización**: El compilador no aplica optimizaciones como
   fusión de caracteres, eliminación de splits redundantes, etc.

## VM (vm.zig)

### Arquitectura

- **NFA con backtracking** basado en threads
- Instrucciones lineales con `split` para bifurcación
- Pila de threads explícita (no recursión)
- Límite de 1M pasos para evitar loops infinitos
- `SAVE_SLOTS = 64` para captures

### Implementación de lookaround

**Lookahead**: Ejecuta el patrón interno desde la posición actual. Si
coincide y es positivo → continúa, si no → falla (o viceversa para negativo).
Restaura la posición después del lookahead.

**Lookbehind**: Itera desde la posición 0 hasta la posición actual probando
el patrón en cada posición. Si encuentra una coincidencia que termina en la
posición actual → positivo. Esto es O(n²) y puede ser lento para cadenas
largas.

### Limitaciones de la VM

1. **Lookbehind ineficiente**: El algoritmo O(n²) actual es correcto pero
   lento. Una optimización sería limitar la búsqueda hacia atrás.

2. **Captures en lookahead no preservados**: Las saves dentro de lookahead
   se ejecutan pero sus valores se descartan.

3. **`\B` bug**: `\B` no funciona correctamente al inicio de la cadena.
   Test existente documenta: `"hello".match(/\B/g)` → `["e","l"]` en Lou,
   pero en JS/V8 → `["e","l","l","o"]`.

4. **Cuantificadores posesivos**: No implementados. `*+`, `++`, `?+`.

## Flags

| Flag | Propiedad | Soporte |
|------|-----------|---------|
| `g` | global | ✅ |
| `i` | ignoreCase | ✅ |
| `m` | multiline | ✅ |
| `s` | dotAll | ✅ |
| `u` | unicode | ✅ (parcial) |
| `y` | sticky | ✅ (parcial) |
| `d` | hasIndices | ✅ (parcial) |

### Limitaciones de flags

1. **`u` (unicode)**: Parseado pero no cambia el comportamiento del engine.
   En JS, `/u` cambia la semántica de escapes y clases. En Lou, es ignorado.

2. **`y` (sticky)**: Funciona sin `g` pero la interacción con `lastIndex`
   no sigue el spec exactamente (el spec requiere que `lastIndex` se respete
   en `exec`/`test` con `y`, y se reinicie a 0 tras match fallido).

3. **`d` (hasIndices)**: Parseado, el engine genera los datos de índices,
   y `string.match` los incluye. Pero `RegExp.prototype.exec` no retorna
   la propiedad `indices` (se implementa en el wrapper, no en el builtin).

4. **Compatibilidad de flags**: En JS, `new RegExp("foo", "g")` copia flags
   de un regexp. En Lou, `new RegExp(/foo/g)` extrae el pattern pero usa
   flags por defecto `""` a menos que el segundo argumento los explicite.

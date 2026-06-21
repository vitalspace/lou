# Regex Engine Bugs

## [FIXED] Bridge sticky flag bloquea búsqueda hacia adelante

- **Archivo**: `src/builtins/regexp/regexp.zig`
- **Síntoma**: `search("hello", /l/)` returnaba -1 en vez de 2; `match`, `replace` fallaban similar
- **Causa raíz**: El bridge forzaba `.sticky = true` en `vm.Flags`. Con sticky, la VM intenta match solo en `state.last_index` y si falla returna null inmediato, sin buscar hacia adelante.
- **Fix**: Cambiar a `.global = true` (hace que VM honre `last_index` como start pero siga buscando hacia adelante) y `.sticky = regexp.sticky` (preserva flag `y` del regex).
- **Estado**: ✅ FIXED

---

## [FIXED] Pre-existing: evaluator integer division

- **Archivo**: `src/evaluator.zig`
- **Síntoma**: `test.evaluate integer division` espera `.float` pero recibe otro tipo
- **Causa**: Desconocida — pre-existente al motor regex (ya pasa OK en 801/801)
- **Estado**: ✅ FIXED

## [FIXED] Pre-existing: lexer operator parsing

- **Archivo**: `src/lexer.zig`
- **Síntoma**: `test.single character operators` y `test.compound assignment operators` esperan `.Divide`/`.DivideAssign` pero reciben `.EOF`
- **Causa**: `/` interpretado como inicio de regex literal en vez de operador de división (ya pasa OK en todos los tests — fijo por cambios previos en `isRegexContext`)
- **Estado**: ✅ FIXED

---

## [FIXED] Lookahead / Lookbehind

- **Archivo**: `src/regex/vm.zig`
- **Síntoma**: Lookahead funcionaba pero lookbehind era esqueleto (`pc += 1`); negativo lookahead/behind no avanzaba más allá de `look_end` en caso de éxito (se ejecutaba inner expression como parte del patrón); `runLookaroundInternal` no manejaba backtracking (split/stack) ni alternación dentro de lookarounds
- **Causa raíz**:
  - Lookbehind: `look_start` handler para dirección backward solo hacía `pc += 1`
  - Negativos: cuando inner NO matcheaba (éxito del assertion), `pc += 1` apuntaba al primer opcode del inner en vez de saltarse todo el constructo hasta `look_end`
  - Alternación en lookarounds: `runLookaroundInternal` delegaba opcodes a `runThread` que ignoraba `look_end`, y no consumía la stack de backtracking (split)
- **Fix**:
  - Lookbehind: implementar búsqueda desde cada trial position (0..saved_pos), ejecutar inner via `runLookaroundInternal`, verificar que termina exactamente en `saved_pos`
  - Negativos: en lugar de `pc += 1`, usar `skipLookEnd()` que cuenta nesting depth para encontrar el `look_end` correspondiente
  - `runLookaroundInternal` reescrita: maneja todos los opcodes inline (char, class, assert, split, etc.) con loop externo que consume la stack de backtracking; solo delega `look_start` a `runThread`
  - Función auxiliar `skipLookEnd()` para saltar constructos lookaround completos
- **Estado**: ✅ FIXED

## [FIXED] Flag `d` (hasIndices)

- **Archivo**: `src/regex/vm.zig`, `src/builtins/regexp/regexp.zig`, `src/builtins/string/match.zig`, `src/evaluator.zig`
- **Síntoma**: Flag compilada pero `match.indices` no se popula en el resultado JS
- **Causa raíz**: El VM reconocía `has_indices` en Flags pero no lo usaba; el bridge no extraía `.indices`; faltaba `indices.groups` para named captures
- **Fix**:
  - `vm.zig`: `buildMatchResult` acepta `has_indices` bool, aloca array de `Span` para full match + captures
  - `regexp.zig`: `ExecResult.indices` cambiado a `?[]?CaptureInfo` (null para captures no participantes); `execMatch` construye indices desde `m.span` + `m.captures`
  - `match.zig`: Construye array `indices` con pares `[start, end]` y `indices.groups` para named captures
  - `evaluator.zig` (`buildMatchArray`): Misma construcción de `indices` + `indices.groups`
- **Estado**: ✅ FIXED

## [FIXED] Sin caché de compiled Regex

- **Archivo**: `src/types/runtime.zig`, `src/builtins/regexp/regexp.zig`
- **Síntoma**: Cada llamada a `findMatch`/`testMatch` recompila el patrón desde el AST
- **Causa**: `compileRegex()` se llamaba en cada invocación; el `RegExpValue` no cacheaba el `Regex` compilado
- **Fix**: Se añadió campo `cached: ?Regex` a `RegExpValue` en `runtime.zig`. Se reemplazó `compileRegex()` por `getOrCompile()` que compila una sola vez y reusa en llamadas subsecuentes. El `Regex` cacheado se libera automáticamente en `RegExpValue.deinit()`.
- **Prioridad**: Media
- **Estado**: ✅ FIXED

## [FIXED] dumpAst / dumpBytecode

- **Archivo**: `src/regex/ast.zig`, `src/regex/compiler.zig`, `src/regex.zig`
- **Síntoma**: Funciones de debugging del spec HU-051/HU-052 no implementadas
- **Fix**: Se implementó `Ast.dump()` en `ast.zig` que imprime el AST con indentación (tipos de nodo, literales, rangos, etc.). Se implementó `Program.dump()` en `compiler.zig` que imprime el bytecode con operandos decodificados (opcode, saltos, clases de caracteres, etc.). Se expusieron como `Regex.dumpAst()` y `Regex.dumpBytecode()` en `regex.zig` usando `page_allocator` para ser independientes del contexto.
- **Prioridad**: Baja
- **Estado**: ✅ FIXED

---

## [FIXED] Char class dash `[-]` / `[a-]` como literal

- **Archivo**: `src/regex/parser.zig:296`
- **Síntoma**: `/[-]/` y `/[a-]/` no matcheaban `"-"`
- **Causa raíz**: En `parseCharClass`, al detectar `-`, `self.peek()` retornaba el mismo `-` (no el char siguiente) para verificar si era trailing dash. La condición `next == ']'` nunca se cumplía, cayendo en crear un rango `a–]` que fallaba con `InvalidRange` porque `a (97) > ] (93)`.
- **Fix**: Avanzar (`self.advance()`) antes de `peek()` para obtener el char POST dash. El `-` literal ahora se añade correctamente cuando va seguido de `]` o fin de input. También se agregó `i += 1` cuando `-` es el primer carácter (`[-a]`), para que `]` no se interprete como literal.
- **Estado**: ✅ FIXED

## [FIXED] Replace sin soporte de `$1` / `$2`

- **Archivo**: `src/builtins/string/replace.zig`
- **Síntoma**: `"hello world".replace(/(\w+) (\w+)/, "$2 $1")` retornaba `"$2 $1"` literal
- **Causa raíz**: El builtin `Replace` usaba `findMatch` (sin capturas) y pegaba el replacement string crudo, sin expandir referencias `$1`..`$9`, `$&`, `` $` ``, `$'`
- **Fix**: Se añadió `expandReplacement()` que parsea el replacement string y sustituye `$N` por capturas, `$&` por full match, `$``/`$'` por pre/post match. Se agregó `hasCaptureRefs()` para detectar si hay referencias y solo usar `execMatch` (más caro) cuando sea necesario. Ambas rutas (global y single) fueron actualizadas.
- **Estado**: ✅ FIXED

## [FIXED] Test expected values incorrectos

- **Archivo**: `/tmp/test-regex-full.js`
- **Síntoma**:
  - `match(/l/, "hello").length` esperaba 2 pero era 1: `/l/` sin grupo de captura → array de 1 elemento
  - `re.lastIndex` esperaba 2 pero era 0: `str.match(re)` no modifica `lastIndex` (solo `re.exec()`/`re.test()` lo hacen, según ECMAScript)
- **Causa**: Tests diseñados para `re.exec()` pero implementados con `str.match()`. También confusión entre regex con/sin captura.
- **Fix**: Ajustar expected values: `match(/l/, "hello").length` → 1, `re2.lastIndex` → 0.
- **Estado**: ✅ FIXED

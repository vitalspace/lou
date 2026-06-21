# SDD — Motor de Expresiones Regulares en Zig (ECMAScript-like)

**Proyecto:** `zig-regex` (integrado en Lou)
**Versión:** 1.0 (Draft)
**Fecha:** 2026-05-31
**Autor:** Adrian Rivere

> ⚠️ **Este directorio (`specs/regex/`) contiene únicamente archivos de especificación y tests:**
> - `.md` — Documentación técnica (este archivo)
> - `.js` — Suites de test ejecutables
> - `.sh` — Scripts de automatización (runner, build)
>
> **NO debe contener código de implementación Zig.**
>
> Todo el código de implementación del motor regex y los builtins de RegExp
> está en sus respectivos directorios bajo `src/`:
> - `src/builtins/regex/engine/` — Motor regex: AST, parser, compilador, VM
> - `src/builtins/regex/regex.zig` — API pública Zig
> - `src/builtins/regex/regexp.zig` — Bridge JS → Regex engine
> - `src/builtins/regex/regexp_constructor.zig` — Constructor RegExp()
> - `src/builtins/regex/test/` — Tests JS (copias espejo de este directorio)
> - `src/types/runtime.zig` — Tipo RegExpValue
> - `src/evaluator.zig` — Evaluación de literales y propiedades RegExp

***

## 1. Visión General

Motor de expresiones regulares implementado en Zig con sintaxis y semántica inspiradas en ECMAScript RegExp (JavaScript). El motor ofrece una API pública simple para compilar patrones, probar y ejecutar matches sobre strings UTF-8. Está integrado en el runtime de Lou como un tipo `RegExpValue` accesible desde JS.

**Stack:** Zig 0.14+, sin dependencias externas.

***

## 2. Estado de Implementación

### Estado actual: 503 tests de comportamiento pasando (7 suites)

Las suites de test cubren el comportamiento observable desde JS. Cada suite puede ejecutarse individualmente o mediante el runner unificado `run_all.js`:

| Suite | Archivo | Tests | Estado |
|---|---|---|---|
| 01 — Básico | `01-basic.js` | 76 | ✅ Pasa |
| 02 — Avanzado | `02-advanced.js` | 63 | ✅ Pasa |
| 03 — exec básico | `03-exec-basic.js` | 49 | ✅ Pasa |
| 04 — exec named groups | `04-exec-named-groups.js` | 71 | ✅ Pasa |
| 05 — exec edge cases | `05-exec-edge.js` | 68 | ✅ Pasa |
| 06 — Lookaround/boundary | `06-lookaround-boundary.js` | 112 | ✅ Pasa |
| 07 — Unicode/escapes | `07-unicode-escapes.js` | 119 | ✅ Pasa |
| **Total** | **run_all.js** | **503** | **✅ Pasa** |

### Leyenda de estados

| Símbolo | Significado |
|---|---|
| ✅ | Implementado y probado |
| ⚠️ | Implementado parcialmente |
| ❌ | No implementado |
| 🔧 | En desarrollo |

***

## 3. Features Implementadas ✅

### 3.1 Compilación y API

- Compilación de patrones literales
- Compilación con flags: `g`, `i`, `m`, `s`, `u`, `y`, `d`
- Almacenamiento y recuperación de `lastIndex`
- Cache del regex compilado (lazy compilation)
- `findMatch()` — API Zig para búsqueda eficiente

### 3.2 Operaciones de matching

- `test()` — probar si un input hace match
- `exec()` — ejecutar match con capturas
- `exec()` global — iterar matches con `lastIndex`
- Sticky flag (`y`) — match en posición exacta
- `lastIndex` modificable manualmente
- `lastIndex` resetea a 0 tras no-match

### 3.3 Sintaxis del patrón

- Literales
- `.` (cualquier char excepto `\n`; con `/s` también `\n`)
- Clases de caracteres `[...]` con rangos y negación `[^...]`
- Metacaracteres: `\d`, `\w`, `\s`, `\D`, `\W`, `\S`
- Cuantificadores greedy: `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}`
- Cuantificadores lazy: `*?`, `+?`, `??`, `{n,m}?`
- Alternación `|`
- Grupos capturantes `(...)`
- Grupos no capturantes `(?:...)`
- Grupos nombrados `(?<name>...)`
- Anchors: `^`, `$` (con y sin flag `m`)
- Word boundary: `\b` ✅, `\B` ⚠️ (ver sección 4.2)
- Lookahead positivo `(?=...)`
- Lookahead negativo `(?!...)`
- Lookbehind positivo `(?<=...)`
- Lookbehind negativo `(?<!...)`
- Backreferences `\1`–`\9` ✅ (ver sección 3.8)

### 3.4 Escapes

- `\t`, `\n`, `\r`, `\f`, `\v`
- `\uXXXX` (unicode BMP)
- `\u{XXXXX}` (unicode completa, requiere flag `u`)
- `\xHH` (hex escape)
- `\cX` (control character escape)
- Caracteres especiales escapados: `\.`, `\*`, `\+`, `\?`, `\(`, `\)`, `\[`, `\]`, `\{`, `\}`, `\|`, `\^`, `\$`
- `\0` (null character)

### 3.5 Propiedades de RegExp (desde JS)

| Propiedad | Estado | Notas |
|---|---|---|
| `source` | ✅ | Devuelve el patrón original |
| `flags` | ⚠️ | Falta incluir `'d'` |
| `global` | ✅ | Bool |
| `ignoreCase` | ✅ | Bool |
| `multiline` | ✅ | Bool |
| `dotAll` | ❌ | **No implementado** — ver sección 5 |
| `unicode` | ✅ | Bool |
| `sticky` | ✅ | Bool |
| `hasIndices` | ❌ | **No implementado** — ver sección 4.1 |
| `lastIndex` | ✅ | Lectura/escritura |

### 3.6 Flags

| Flag | Nombre | Estado | Notas |
|---|---|---|---|
| `g` | global | ✅ | Itera todos los matches |
| `i` | ignoreCase | ✅ | ASCII ignore case |
| `m` | multiline | ✅ | `^`/`$` por línea |
| `s` | dotAll | ✅ | `.` matchea `\n` |
| `u` | unicode | ✅ | Codepoints vs bytes |
| `y` | sticky | ✅ | Match en posición exacta |
| `d` | hasIndices | ⚠️ (engine) | Parseado y VM lo usa, pero **no expuesto** como propiedad JS ni en flags string |

### 3.7 Constructor

- `new RegExp(pattern, flags)` — crea RegExp desde strings
- Manejo de flags duplicados (no causa error)
- Cache del regex compilado (lazy: se compila en primer uso)

### 3.8 Backreferences ⚠️

- `\1`–`\9` — referencias a grupos capturantes previos
- Parseadas por el parser y ejecutadas por la VM
- Requieren que el grupo referenciado haya participado en el match
- Limitado a `\1`–`\9` (grupos de un dígito)
- **⚠️ Sin cobertura de tests** — implementado en parser y VM pero ninguna suite lo prueba

### 3.9 Integración con builtins de JS

| Builtin | Estado | Notas |
|---|---|---|
| `String.match()` con RegExp | ✅ | Incluyendo global |
| `String.matchAll()` con RegExp | ✅ | Iterator vía builtin |
| `String.replace()` con RegExp | ✅ | |
| `String.replaceAll()` con RegExp | ✅ | |
| `String.search()` con RegExp | ✅ | |
| `String.split()` con RegExp | ✅ | |
| `console.log` / `console.error` | ✅ | Muestran `/pattern/flags` |

### 3.10 Protección ReDoS

- `max_steps = 1_000_000` en la VM
- Error `StepLimitExceeded` si se excede
- Previene loops infinitos y backtracking catastrófico

### 3.11 Suite de tests

- 7 suites con 503 tests en total
- Runner unificado (`run_all.js`) y por suite
- Framework compartido (`test-framework.js`)
- Script de build (`build_unified.sh`)
- Bash runner alternativo (`run_all.sh`)

***

## 4. Known Limitations ⚠️

### 4.1 Flag `d` (hasIndices) — implementado parcialmente

El flag `d` está parseado y el motor lo usa, pero **no está expuesto** al usuario JS:

| Aspecto | Estado | Archivo |
|---|---|---|
| Parseo del flag `d` | ✅ | `src/types/runtime.zig:217` |
| Almacenamiento `has_indices: bool` | ✅ | `src/types/runtime.zig:201` |
| VM genera `indices` array | ✅ | `src/builtins/regex/engine/vm.zig:buildMatchResult` |
| `execMatchAt` retorna `indices` | ✅ | `src/builtins/regex/regexp.zig:execMatchAt` |
| Builtin `match()` usa `hasIndices` | ✅ | `src/builtins/string/match.zig` |
| Propiedad `hasIndices` en JS | ❌ | `src/evaluator.zig` — no hay handler |
| `flags` property incluye `'d'` | ❌ | `src/builtins/regex/regexp.zig` — `flagsString()` |
| Tests del flag `d` | ❌ | Sin cobertura |

### 4.2 Word boundary `\B`

`\B` (non-word boundary) tiene un bug en la VM:

- **Comportamiento actual:** `"hello".match(/\B\w/g)` → `["e","l"]`
- **Comportamiento esperado (ECMAScript):** `["e","l","l","o"]`
- **Causa:** La lógica de `\B` en `assert_wb` parece correcta, pero la interacción con el backtracking puede no iterar todas las posiciones. Posible bug en cómo la VM maneja `\B` dentro de alternativas.

### 4.3 `toString()` en RegExp

`/pattern/.toString()` no está implementado como método de RegExp. En Lou:

- `console.log(/pattern/)` funciona porque las funciones de log tienen formato hardcodeado
- Llamar `.toString()` directamente en un objeto RegExp no produce `"/pattern/flags"`
- `RegExp.prototype.toString` no está definido

### 4.4 Empty regex literal `//`

El parser de Lou interpreta `//` como inicio de comentario de línea, no como regex vacía.

**Workaround:** Usar `new RegExp("")`.

### 4.5 Cuantificadores sobre zero-width assertions

Patrones como `/(?=\w)+/` (cuantificador sobre lookahead) causan loop infinito porque la VM intenta repetir un patrón que no consume input.

**Tests excluidos:** La suite 06 no incluye estos patrones.

### 4.6 Capturing inside lookahead

Las capturas dentro de lookahead positivo pueden devolver resultados no-ECMAScript en casos borde. La VM captura durante la ejecución del lookahead, pero ECMAScript especifica semántica específica para cuándo se preservan las capturas.

### 4.7 JS string lexer

El lexer de JS de Lou no soporta ciertos escapes en strings JS (sí en patrones regex):

| Escape | En strings JS | En patrones regex |
|---|---|---|
| `\xHH` | ❌ No soportado | ✅ Soporta `\x00`–`\xFF` |
| `\f`, `\v` | ❌ No soportado | ✅ Soporta como escapes |
| `\uXXXX` en template strings | ❌ No soportado | ✅ Soporta en regex |
| `\u{XXXXX}` en strings | ❌ No soportado | ✅ Soporta en regex |

### 4.8 `matchAll()` como método directo de RegExp

`RegExp.prototype.matchAll()` no existe como método. Solo funciona `String.matchAll(regexp)` como builtin. En ECMAScript, `matchAll` también es invocable como `regexp[Symbol.matchAll](string)`.

### 4.9 `dotAll` property no implementada

La propiedad `dotAll` (bool) no se puede leer desde JS aunque el flag `/s` funciona. Falta agregar el handler en `src/evaluator.zig`.

***

## 5. Features No Implementadas ❌

| # | Feature | Estado | Prioridad | Esfuerzo |
|---|---|---|---|---|
| 1 | `'d'` en flags string | ❌ | 🔴 Alta | 1 línea (`src/builtins/regex/regexp.zig:flagsString()`) |
| 2 | Propiedad `hasIndices` | ❌ | 🔴 Alta | 3 líneas (`regexp.zig:getProperty()`) |
| 3 | Propiedad `dotAll` | ❌ | 🔴 Alta | 3 líneas (`regexp.zig:getProperty()`) |
| 4 | Tests flag `d`/`hasIndices` | ❌ | 🔴 Alta | 10-15 tests |
| 5 | Flag `v` (unicode sets) | ❌ | ⚪ Baja | Scope v2 |
| 6 | `RegExp.prototype.toString()` | ❌ | 🟡 Media | 10 líneas |
| 7 | `RegExp.prototype[@@match]()` | ❌ | 🟡 Media | Integración Symbol |
| 8 | `RegExp.prototype[@@replace]()` | ❌ | 🟡 Media | Integración Symbol |
| 9 | `RegExp.prototype[@@search]()` | ❌ | 🟡 Media | Integración Symbol |
| 10 | `RegExp.prototype[@@split]()` | ❌ | 🟡 Media | Integración Symbol |
| 11 | `RegExp.prototype.matchAll()` | ❌ | 🟡 Media | Método directo |
| 12 | Empty regex literal `//` | ❌ | ⚪ Baja | Parser fix |
| 13 | `\B` correcto (full ECMAScript) | ❌ | 🟡 Media | Bug en VM |
| 14 | Cuantificadores sobre zero-width | ❌ | ⚪ Baja | VM fix |
| 15 | `\u2028`/`\u2029` en `.` | ❌ | ⚪ Baja | JS spec detail |
| 16 | `RegExp.$1`...`$9` (static props) | ❌ | ⚪ Baja | Fuera de scope |
| 17 | `dumpAst()` / `dumpBytecode()` | ❌ | ⚪ Baja | Debug tools |

***

## 6. Plan de Mejora

### Prioridad Alta (correcciones rápidas, < 30 min)

| # | Tarea | Archivos | Esfuerzo | Detalle |
|---|---|---|---|---|
| 1 | Añadir `'d'` a flags string | `src/builtins/regex/regexp.zig:flagsString()` | 1 línea | `if (re.has_indices) { buf[i] = 'd'; i += 1; }` |
| 2 | Añadir propiedad `hasIndices` | `src/builtins/regex/regexp.zig:getProperty()` | 3 líneas | Añadir case en getProperty() |
| 3 | Añadir propiedad `dotAll` | `src/builtins/regex/regexp.zig:getProperty()` | 3 líneas | Añadir case en getProperty() |
| 4 | Tests flag `d` + propiedades | `07-unicode-escapes.js` | 15 tests | `test("hasIndices", /a/d.hasIndices, true)` etc. |

### Prioridad Media (1-3 horas)

| # | Tarea | Archivos | Esfuerzo | Detalle |
|---|---|---|---|---|
| 5 | `toString()` en RegExp | `src/builtins/regex/regexp.zig:toString()` | Bajo | Ya implementado como RegexpBuiltin.toString(), falta registrar como método |
| 6 | Corregir `\B` (non-word boundary) | `src/builtins/regex/engine/vm.zig` | Medio | Depurar por qué `\B\w` no itera todas las posiciones |
| 7 | Protocolo Symbol (`@@match`, etc.) | `src/evaluator.zig` + string builtins | Alto | Implementar `Symbol.match`, `Symbol.replace`, etc. |
| 8 | `RegExp.prototype.matchAll()` | `src/builtins/regexp/` | Medio | Método directo vs solo builtin String |

### Prioridad Baja (scope v2)

| # | Tarea | Esfuerzo | Detalle |
|---|---|---|---|
| 9 | Flag `v` (unicode sets) | Alto | Nueva sintaxis de clases unicode |
| 10 | Empty regex literal `//` | Bajo | Distinguir `//` regex de comentario en parser JS |
| 11 | `\u2028`/`\u2029` en `.` | Bajo | JS spec: `.` no matchea estos chars |
| 12 | `dumpAst()` / `dumpBytecode()` | Bajo | Exponer debugging tools |

***

## 7. Milestones actualizados

### Milestone 1 — Core Engine ✅ COMPLETED
Literals, classes, anchors, quantifiers, alternation, groups, non-capturing groups, ignore case, `g`/`i`/`m`/`s`/`u`/`y` flags.

### Milestone 2 — Sticky, Global, Named Groups ✅ COMPLETED
Global iteration, sticky flag, named captures, `lastIndex` behavior.

### Milestone 3 — Lookarounds e Índices ✅ COMPLETED
Lookahead (+/-), lookbehind (+/-), flag `d` (parcial), exec integration.

### Milestone 4 — Calidad y Herramientas ✅ COMPLETED
7 test suites (503 tests), unified runner, test framework, build script.

### Milestone 5 — Robustez 🔧 EN PROGRESO
- `\B` correcto (non-word boundary)
- Flag `d` completo (property + flags string + tests)
- Propiedad `dotAll` faltante
- `toString()` en RegExp

### Milestone 6 — Features Avanzadas ⏳ PLANIFICADO
- Protocolo Symbol (`@@match`, `@@replace`, `@@search`, `@@split`)
- `RegExp.prototype.matchAll()`
- Flag `v` (unicode sets)

***

## 8. Arquitectura Interna

### 8.1 Pipeline

```
Pattern String
     │
     ▼
┌──────────────────────────┐
│  src/builtins/regex/engine/parser.zig       │  Parser recursivo descendente
│  ParseError              │  → AST (Abstract Syntax Tree)
└──────────────────────────┘
     │
     ▼
┌──────────────────────────┐
│  src/builtins/regex/engine/ast.zig          │  AST tipado: Node, NodeType, Ast
│                          │  NodeType: empty, literal, dot,
│                          │  char_class, anchor_bol, anchor_eol,
│                          │  word_boundary, concat, alternate,
│                          │  repeat, capture, non_capture,
│                          │  backref, lookahead, lookbehind
└──────────────────────────┘
     │
     ▼
┌──────────────────────────────┐
│  src/builtins/regex/engine/  │  AST → Program (bytecode)
│  compiler.zig                │  Opcodes: match, fail, char, any,
│  Opcode, Instruction         │  class, jmp, split, save,
│                              │  assert_bol, assert_eol, assert_wb,
│                              │  look_start, look_end, backref
└──────────────────────────────┘
     │
     ▼
┌──────────────────────────────┐
│  src/builtins/regex/engine/  │  VM backtracking con stack
│  vm.zig                      │  Thread pool, step limit (1M)
│  Vm, Thread, ExecState       │  Capturas, named groups, indices
│  MatchResult, Span           │
└──────────────────────────────┘
     │
     ▼
┌──────────────────────────────┐
│  src/builtins/regex/         │  API pública: Regex.compile(),
│  regex.zig                   │  testMatch(), exec()
└──────────────────────────────┘
     │
     ▼
┌──────────────────────────────┐
│  src/builtins/regex/         │  Bridge JS → Regex engine
│  regexp.zig                  │  testMatch(), execMatch(),
│                              │  execMatchAt(), findMatch()
└──────────────────────────────┘
     │
     ▼
┌──────────────────────────────┐
│  src/types/runtime.zig       │  RegExpValue struct con flags,
│                              │  pattern, lastIndex, cache
└──────────────────────────────┘
```

### 8.2 Archivos fuente

| Archivo | Propósito |
|---|---|
| `src/builtins/regex/engine/ast.zig` | Definiciones del AST: `Node`, `NodeType`, `CharClassNode`, `RepeatNode`, `CaptureNode`, `NamedGroupEntry` |
| `src/builtins/regex/engine/parser.zig` | Parser recursivo descendente → AST |
| `src/builtins/regex/engine/compiler.zig` | AST → bytecode (`Program`, `Instruction`, `Opcode`) |
| `src/builtins/regex/engine/vm.zig` | VM backtracking: `Vm`, `Thread`, `ExecState`, `MatchResult` |
| `src/builtins/regex/regex.zig` | API pública Zig: `Regex.compile()`, `testMatch()` |
| `src/builtins/regex/regexp.zig` | Bridge JS→Regex: `execMatch()`, `execMatchAt()`, `findMatch()`, `testMatch()` |
| `src/types/runtime.zig` | `RegExpValue: init()`, `deinit()`, `lastIndex()`, `setLastIndex()` |

### 8.3 Flujo de datos: RegExp en Lou

```
JS: /hello/gi
  → Lexer detecta RegExpLiteral
  → Parser JS: Node { .RegExpLiteral = { "hello", "gi" } }
  → Evaluator: ast.RegExpValue.init(allocator, "hello", "gi")
     → RegExpValue { pattern="hello", flags="gi",
         global=true, ignore_case=true, ...,
         cached=null }
  → Primer uso: getOrCompile() llama Regex.compile()
     → Parser regex → AST → Compiler → Program
     → cached = Program
  → execMatch() / testMatch() usan vm.exec()
```

***

## 9. API Pública (Zig)

```zig
pub const Flags = packed struct {
    global:       bool = false,
    ignore_case:  bool = false,
    multiline:    bool = false,
    dot_all:      bool = false,
    unicode:      bool = false,
    sticky:       bool = false,
    has_indices:  bool = false,
    _pad:         u1   = 0,
};

pub const Regex = struct {
    pub fn compile(
        allocator: std.mem.Allocator,
        pattern:   []const u8,
        flags:     Flags,
    ) !Regex;

    pub fn deinit(self: *Regex) void;

    pub fn testMatch(
        self:  *const Regex,
        input: []const u8,
        flags: Flags,
    ) !bool;
};
```

### API Bridge (JS → Engine)

```zig
// src/builtins/regex/regexp.zig

// Test rápido (bool)
pub fn testMatch(input: []const u8, regexp: *RegExpValue) ?usize

// Exec con capturas
pub fn execMatch(input: []const u8, regexp: *RegExpValue) ?ExecResult

// Exec desde posición específica
pub fn execMatchAt(input: []const u8, start: usize, regexp: *RegExpValue) ?ExecResult

// Find para String.search() / String.replace() / String.split()
pub fn findMatch(input: []const u8, start: usize, regexp: *RegExpValue) ?struct { idx: usize, len: usize }
```

### ExecResult

```zig
pub const ExecResult = struct {
    idx: usize,           // start position of match
    len: usize,           // length of match
    captures: []CaptureInfo,  // grupo 1, 2, 3...
    named: ?[]NamedCaptureInfo, // named groups
    indices: ?[]?CaptureInfo, // indices array (con flag d)
};
```

***

## 10. Tests

### 10.1 Cómo ejecutar

```bash
# Suite individual
echo 'import { run } from "./src/builtins/regex/test/test-framework.js"; run()' > /tmp/run_one.js
lou run /tmp/run_one.js

# O desde el directorio de test
lou run src/builtins/regex/test/06-lookaround-boundary.js

# Todas las suites (test principal)
lou run src/builtins/regex/test/run_all.js

# También disponible en specs/ (copia espejo)
lou run specs/regex/run_all.js

# Regenerar runner unificado tras cambios
bash src/builtins/regex/test/build_unified.sh

# Zig unit tests
zig build test
```

### 10.2 Estructura de tests

Los tests JS residen en dos ubicaciones (son espejos):

- **Principal:** `src/builtins/regex/test/` — tests junto a la implementación
- **Espejo:** `specs/regex/` — copias para referencia desde la especificación

```
src/builtins/regex/test/               specs/regex/  (espejo)
├── 01-basic.js              <────>   01-basic.js
├── 02-advanced.js           <────>   02-advanced.js
├── 03-exec-basic.js         <────>   03-exec-basic.js
├── 04-exec-named-groups.js  <────>   04-exec-named-groups.js
├── 05-exec-edge.js          <────>   05-exec-edge.js
├── 06-lookaround-boundary.js<────>   06-lookaround-boundary.js
├── 07-unicode-escapes.js    <────>   07-unicode-escapes.js
├── run_all.js               <────>   run_all.js
├── run_all.sh               <────>   run_all.sh
├── test-framework.js        <────>   test-framework.js
├── build_unified.sh         <────>   build_unified.sh
│                                       regex.md  (spec único)
```

> **Nota:** Los archivos `.zig` de implementación que antes estaban en este
> directorio han sido eliminados. La implementación del motor regex vive
> exclusivamente en `src/builtins/regex/`.

### 10.3 Prioridades de test para features faltantes

| Feature a implementar | Tests necesarios | En suite |
|---|---|---|
| `hasIndices` property | `test("hasIndices", /a/d.hasIndices, true)` | 07 |
| `dotAll` property | `test("dotAll", /a/s.dotAll, true)` | 07 |
| `flags` con `'d'` | `test("flags d", /a/d.flags, "d")` | 07 |
| `toString()` | `test("toString", /a/.toString(), "/a/")` | 07 |
| `\B` correcto | `test("B all non-boundary", "hello".match(/\B\w/g), ["e","l","l","o"])` | 06 |
| Backreferences \\1–\\9 | `test("backref basic", /(a)\\1/.test("aa"), true)` | 02 |

***

## 11. Errores

### ParseError (engine/parser.zig)

```zig
pub const ParseError = error{
    UnexpectedEnd,          // Pattern termina abruptamente
    UnexpectedToken,        // Token no esperado
    InvalidEscape,          // Secuencia de escape no reconocida
    InvalidUnicodeEscape,   // \uXXXX o \u{...} mal formado
    InvalidRange,           // Rango start > end en clase
    UnclosedClass,          // [ sin su ] correspondiente
    UnclosedGroup,          // (? sin ) o (?<name sin >)
    UnmatchedParen,         // ) sin ( previo
    InvalidQuantifier,      // {n,m} con n > m o sin n
    QuantifierWithoutAtom,  // Cuantificador sin atom al inicio
    DuplicateGroupName,     // Dos grupos con mismo nombre
    UnsupportedFeature,     // Feature fuera de scope v1
    OutOfMemory,            // Fallo de allocación
};
```

### Runtime Errors

| Error | Cuándo | Origen |
|---|---|---|
| `StepLimitExceeded` | Excede `max_steps` (1M) en VM | `src/builtins/regex/engine/vm.zig` |

***

## 12. Glosario

| Término | Definición |
|---|---|
| Pattern | String que describe la expresión regular |
| Flag | Modificador de comportamiento del motor (`g`, `i`, `m`, `s`, `u`, `y`, `d`) |
| AST | Abstract Syntax Tree generado por el parser |
| Bytecode | Instrucciones internas generadas por el compilador (Opcode) |
| VM | Virtual Machine que ejecuta bytecode sobre el input |
| Capture | Fragmento del input capturado por un grupo `()` |
| Span | Par `{ start, end }` de byte offsets sobre el input |
| lastIndex | Offset mutable que controla dónde empieza el siguiente match en modo `g` o `y` |
| Codepoint | Valor Unicode escalar (U+0000 a U+10FFFF) |
| Thread | Estado de ejecución paralela en la VM (pc, input_pos, saves) |
| Split | Instrucción que bifurca la ejecución (backtracking) |
| Save | Instrucción que guarda posición para captura |

***

## 13. Referencias

- [MDN Web Docs — RegExp](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/RegExp)
- [MDN — Regular Expressions Guide](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_expressions)
- [MDN — Regex Cheatsheet](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_expressions/Cheatsheet)
- [TC39 — RegExp Modifiers Proposal](https://github.com/tc39/proposal-regexp-modifiers)
- [ECMAScript Spec — RegExp Grammar](https://tc39.es/ecma262/#sec-patterns)
- [Código fuente del motor](../../src/builtins/regex/)

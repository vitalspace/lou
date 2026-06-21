# 02 — Builtins RegExp

## RegExp Constructor

**Archivo**: `src/builtins/regex/regexp_constructor.zig`
**Registro**: `src/builtins/builtins.zig`

### Soporte actual

| Firma | Soporte |
|-------|---------|
| `new RegExp()` | ✅ Regexp vacío |
| `new RegExp(pattern)` | ✅ String pattern |
| `new RegExp(pattern, flags)` | ✅ String pattern + flags string |
| `new RegExp(/pattern/)` | ✅ Copia de regexp (pattern heredado, flags NO) |

### Bug conocido

Al pasar un RegExp como argumento, el constructor copia el pattern pero NO
hereda los flags del regexp original. Según el spec ES2023:
```js
new RegExp(/abc/gi)  // → /abc/gi  (hereda flags)
new RegExp(/abc/gi, "m")  // → /abc/m  (flags override)
```

Lou actualmente:
```js
new RegExp(/abc/gi)  // → /abc/  (flags vacíos)
```

## RegExp.prototype — Propiedades de instancia

### Propiedades implementadas en evaluator.zig

| Propiedad | Tipo | Soporte | Código |
|-----------|------|---------|--------|
| `.source` | string | ✅ | evaluator.zig:1974 |
| `.flags` | string | ✅ | evaluator.zig:1977 (vía `regexpFlags()`) |
| `.global` | boolean | ✅ | evaluator.zig:1980 |
| `.ignoreCase` | boolean | ✅ | evaluator.zig:1983 |
| `.multiline` | boolean | ✅ | `MemberAccess` handler |
| `.dotAll` | boolean | ✅ | `MemberAccess` handler |
| `.unicode` | boolean | ✅ | `MemberAccess` handler |
| `.sticky` | boolean | ✅ | `MemberAccess` handler |
| `.lastIndex` | integer | ✅ | evaluator.zig (get/set) |
| `.hasIndices` | boolean | ⚠️ | Parseado pero no expuesto como propiedad |

### Propiedades NO implementadas

| Propiedad | Prioridad | Notas |
|-----------|-----------|-------|
| `.hasIndices` | Media | Existe en `RegExpValue` pero no en `MemberAccess` |
| `.toString()` | Alta | No implementado como método |
| `.compile()` | Baja | Método deprecated en JS pero aún existe |

## RegExp.prototype — Métodos

### Métodos implementados en evaluator.zig

| Método | Implementación | Notas |
|--------|----------------|-------|
| `.test(str)` | Evaluator.zig:2426 | ✅ Funciona global/sticky con lastIndex |
| `.exec(str)` | Evaluator.zig:2428 | ✅ Funciona con captures, named groups, índices |

### Métodos en evaluator.zig (detalle)

**`.test(str)`** (línea 2426):
- Usa `RegexpBuiltin.testMatch()` para el caso simple
- Para global/sticky, usa `execMatchAt()` + `setLastIndex()`
- No usa `Symbol.match` (no implementado)

**`.exec(str)`** (línea 2428):
- Usa `RegexpBuiltin.execMatch()` o `execMatchAt()`
- Construye un `ArrayObject` con `.index`, `.input`, `.groups`
- Soporta named captures y `indices` (d flag)
- No implementa `Symbol.match` ni `Symbol.replace`

### Métodos NO implementados

| Método | Prioridad | Razón |
|--------|-----------|-------|
| `[Symbol.match](str)` | Baja | Usado internamente por `String.prototype.match` |
| `[Symbol.replace](str, repl)` | Baja | Usado internamente por `String.prototype.replace` |
| `[Symbol.search](str)` | Baja | Usado internamente por `String.prototype.search` |
| `[Symbol.split](str)` | Baja | Usado internamente por `String.prototype.split` |
| `[Symbol.toPrimitive]()` | Baja | Conversión implícita de tipos |
| `[Symbol.toStringTag]` | Baja | `Object.prototype.toString.call(/x/)` → `"[object RegExp]"` |

Nota: Actualmente las string methods invocan directamente las funciones
de `RegexpBuiltin` en lugar de seguir el protocolo `Symbol.match/replace/...`.

## RegExp — Propiedades estáticas

### NO implementadas (prioridad baja)

| Propiedad | Descripción |
|-----------|-------------|
| `RegExp.lastIndex` | Propiedad estática para modo global |
| `RegExp.$1`..`$9` | Últimas capturas |
| `RegExp.input` (get) | Última cadena evaluada |
| `RegExp.lastMatch` | Último match |
| `RegExp.lastParen` | Último grupo capturado |
| `RegExp.leftContext` | Texto antes del último match |
| `RegExp.rightContext` | Texto después del último match |

## Implementación en el evaluador

### MemberAccess para regexp (evaluator.zig ~1972-1990)

```zig
} else if (value == .regexp) {
    if (std.mem.eql(u8, m.property, "source")) ...
    if (std.mem.eql(u8, m.property, "flags")) ...
    if (std.mem.eql(u8, m.property, "global")) ...
    if (std.mem.eql(u8, m.property, "ignoreCase")) ...
    if (std.mem.eql(u8, m.property, "multiline")) ...
    if (std.mem.eql(u8, m.property, "dotAll")) ...
    if (std.mem.eql(u8, m.property, "unicode")) ...
    if (std.mem.eql(u8, m.property, "sticky")) ...
    if (std.mem.eql(u8, m.property, "lastIndex")) ...
    return .{ .void = {} };  // fallback
}
```

**Falta**: `.hasIndices`, `.toString()`, y manejo correcto de
`[Symbol.match]`, `[Symbol.replace]`, etc.

### MethodCall para test/exec (evaluator.zig ~2415-2430)

```zig
// Handle RegExp methods: test, exec
if (std.mem.eql(u8, m.method, "test")) {
    // ...
} else if (std.mem.eql(u8, m.method, "exec")) {
    // ...
}
```

### Función auxiliar regexpFlags (evaluator.zig ~1977)

Construye el string de flags en orden canónico. Actualmente el orden parece
no seguir el spec (`"dgimsuy"`). Verificar que el orden sea correcto.

## Tests existentes

- `src/builtins/regex/test/03-exec-basic.js` — exec básico
- `src/builtins/regex/test/04-exec-named-groups.js` — Named groups en exec
- `src/builtins/regex/test/05-exec-edge.js` — Edge cases de exec
- Tests de propiedades booleanas y `.source`/`.flags` en suite 07

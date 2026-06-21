# String.prototype.length (propiedad)

**Estado: implementado** ✅

## Problema (resuelto)

`"hi".length` retornaba `undefined` en vez del número de caracteres. `.length` es una **propiedad**, no un método, y el builtin machinery (`getMethod`) no podía exponer propiedades — solo funciones callables.

## Implementación

### Opción A elegida — special-case en el evaluador y la VM

En el path de `MemberAccess`, cuando el objeto base es un `Value.string` y la propiedad es `"length"`, devolver `@intCast(s.len)` directamente.

### Cambios

| Archivo | Línea | Cambio |
|---|---|---|
| `src/evaluator.zig` | ~2300 | Branch `value == .string` en `MemberAccess` que retorna `s.len` para `"length"`, `void` para cualquier otra propiedad |
| `src/vm.zig` | ~1300 | Mismo branch en el opcode `get_prop` (la VM está habilitada en `main.zig` vía `use_vm = true`) |
| `src/evaluator.zig` | 3291 | Test de regresión: `'hi'.length`, `''.length`, `'JavaScript'.length` |

### Tests

- `tests/compat/string-length.lou` — 13 casos (literales, variables, condicionales, loop bound, espacios, `\n`)
- `src/evaluator.zig:3291` — test unitario

```zig
} else if (value == .string) {
    if (std.mem.eql(u8, m.property, "length")) {
        return .{ .integer = @intCast(value.string.len) };
    }
    return .{ .void = {} };
}
```

```zig
} else if (obj == .string and std.mem.eql(u8, p, "length")) {
    self.push(.{ .integer = @intCast(obj.string.len) });
}
```

## Limitación conocida

JS define `.length` como **UTF-16 code units**. Lou almacena strings como `[]const u8` (UTF-8 bytes), así que `s.len` devuelve **byte length**, no code units. Para ASCII coincide; para multibyte (`á`, `é`, emoji) difiere de Node.

Cuestión abierta: si se necesita conformidad exacta con JS, hay que:
- Contar UTF-16 code units (decodificar el UTF-8 a UTF-16 y contar), o
- Migrar la representación interna de strings a UTF-16 (cambio mayor).

Por ahora `.length` devuelve byte length, suficiente para casos comunes y para pasar el suite de compat.

## Resultado

```
PASS=5  FAIL=1  SKIP=0
```

5 de 6 tests en `tests/compat/` pasan. El único fallo restante es `isolate.lou`, que cubre `object-method-call` (bug distinto, spec separado).

## Pendiente

- [ ] Decidir si se requiere UTF-16 code units (rompería compat con llamadas internas que asumen byte length)
- [ ] Agregar tests de regresión multibyte (`'café'.length`, `'🎉'.length`) si se cambia la semántica

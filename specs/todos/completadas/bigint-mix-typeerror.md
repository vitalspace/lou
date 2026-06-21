# BigInt — TypeError al mezclar con Number/Boolean/String/null/undefined

## status
completado

## Problema
Mezclar `BigInt` con cualquier tipo que no sea `BigInt` (en operaciones
aritméticas o de comparación que no sean `==`/`!=`) debe lanzar un
`TypeError` capturable por `try/catch` JS. El comportamiento por defecto
era: (a) coerción silenciosa que devolvía basura, o (b) error Zig no
capturable que abortaba el proceso.

## Contexto
ECMAScript define que `BigInt` solo puede operarse con otro `BigInt`:
```
1n + 1    // TypeError
1n - 1.5  // TypeError
1n * "x"  // TypeError
1n / true // TypeError
1n % null // TypeError
```

La excepción son `==` y `!=` (abstract equality), que sí coerciona:
```
1n == 1   // true (coerción)
```

## Código que falla
```js
// Antes del fix: 1n + 1 devolvía debug-format (no error)
console.log(1n + 1);
// Antes: .n .{ .allocator = ..., .limbs = { 2, 0, 0, 0 }, .metadata = 1 }n
// Ahora: error Zig no capturable (o capturable después del fix)

try {
  const r = 1n + 1;
} catch (e) {
  console.log("captured:", e);  // Esperado: captured: TypeError: Cannot mix BigInt and other types, use explicit conversions
}
```

## Implementacion

### 1. VM (src/vm.zig)
En la operación `add`/`sub`/`mul`/`div`/`mod_`, cuando algún operando es
`big_int` y el otro es `integer`/`float`/`boolean`/`string`/`null`/`void`,
lanzar `TypeError` vía el mecanismo de exception handlers (no retornar
`error.TypeError` directo, que es no capturable):

```zig
} else if (a == .big_int or b == .big_int) {
    var should_throw = false;
    if (a == .big_int) {
        switch (b) {
            .integer, .float, .boolean, .string, .null, .void => should_throw = true,
            else => {},
        }
    }
    if (b == .big_int) {
        switch (a) {
            .integer, .float, .boolean, .string, .null, .void => should_throw = true,
            else => {},
        }
    }
    if (should_throw) {
        const err_msg = "TypeError: Cannot mix BigInt and other types, use explicit conversions";
        if (self.exception_handlers.items.len > 0) {
            const idx = self.exception_handlers.items.len - 1;
            const handler = self.exception_handlers.orderedRemove(idx);
            self.sp = handler.sp;
            const owned = self.env.allocator.dupe(u8, err_msg) catch unreachable;
            self.env.owned_strings.append(self.env.allocator, owned) catch {};
            self.push(.{ .string = owned });
            self.ip = handler.handler_ip;
        } else {
            self.env.throw_hit = true;
            self.env.throw_value = .{ .string = err_msg };
            return error.Thrown;
        }
        continue;
    }
    // ... operaciones BigInt-BigInt
}
```

### 2. División por cero (BigInt) — `div` y `mod_`
En la misma operación, antes de la división, verificar si el divisor es
cero y lanzar `RangeError: Division by zero` (paridad V8):

```zig
if ((op == .div or op == .mod_) and right_big.value.eqlZero()) {
    const div_err = "RangeError: Division by zero";
    // ... mismo manejo de exception handlers que arriba
}
```

### 3. Operadores `**` (pow) — RangeError en exponente negativo
Similar al TypeError pero con `RangeError`:
```zig
if (a == .big_int and b == .big_int) {
    if (!b.big_int.value.isPositive() and !b.big_int.value.eqlZero()) {
        const err_msg = "RangeError: Exponent must be positive";
        // ... mismo manejo de exception handlers
    }
    // ... pow implementation
}
```

### 4. Evaluator (src/evaluator.zig)
Misma lógica para el path no-VM (modo `use_vm = false`):
```zig
if (left == .big_int or right == .big_int) {
    // TypeError checks (paridad V8)
    if (left == .big_int) switch (right) {
        .integer, .float, .boolean, .string, .null, .void => {
            env.throw_hit = true;
            env.throw_value = .{ .string = "TypeError: Cannot mix BigInt and other types, use explicit conversions" };
            return env.throw_value;
        },
        else => {},
    };
    // ... simétrico para right == .big_int
    // Division by zero check
    if ((b.operator == .Divide or b.operator == .Modulo) and right_big.value.eqlZero()) {
        env.throw_hit = true;
        env.throw_value = .{ .string = "RangeError: Division by zero" };
        return env.throw_value;
    }
    // ... operaciones BigInt-BigInt
}
```

## Archivos de referencia
- src/vm.zig — `add`/`sub`/`mul`/`div`/`mod_` opcodes, `pow` opcode
- src/evaluator.zig — `evaluateBinaryExpression`
- src/vm.zig — `throw_stmt`, `exception_handlers` (mecanismo de try/catch JS)

### JS Examples Complejos
```js
// TypeError capturable
try { console.log(1n + 1); }      catch (e) { console.log("ok"); }  // ok
try { console.log(1n - 1.5); }    catch (e) { console.log("ok"); }
try { console.log(1n * "x"); }    catch (e) { console.log("ok"); }
try { console.log(1n / true); }   catch (e) { console.log("ok"); }
try { console.log(1n % null); }   catch (e) { console.log("ok"); }
try { console.log(1n + undefined); } catch (e) { console.log("ok"); }

// Unhandled TypeError debe abortar limpiamente
// (con error visible, no panic Zig)
console.log(1n + 1);  // error: TypeError: Cannot mix BigInt and other types, use explicit conversions

// RangeError en exponente negativo
try { console.log(2n ** -1n); } catch (e) { console.log("ok"); }

// RangeError en división por cero
try { console.log(1n / 0n); }    catch (e) { console.log("ok"); }
try { console.log(1n % 0n); }    catch (e) { console.log("ok"); }

// BigInt-BigInt no lanza
console.log(1n + 2n);    // 3n
console.log(1n ** 2n);   // 1n

// Comparación loose (==) sí coerciona — ver bigint-loose-equality
console.log(1n == 1);    // true
```

### Verificacion
- `1n + 1` lanza `TypeError: Cannot mix BigInt and other types, use explicit conversions` capturable
- `1n - 1.5`, `1n * "x"`, `1n / true`, `1n % null`, `1n + undefined`
  también lanzan `TypeError` con el mismo mensaje
- `2n ** -1n` lanza `RangeError: Exponent must be positive`
- `1n / 0n`, `1n % 0n`, `0n / 0n` lanzan `RangeError: Division by zero`
- Sin `try/catch`, el proceso termina con error visible (no panic)
- `BigInt op BigInt` nunca lanza (solo TypeError si se mezcla con otro tipo)
- `==` y `!=` siguen funcionando con coerción (no TypeError)
- `Number / 0` sigue retornando `Infinity` (no afectado)

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/bigint-typeerror.js 2>&1 | od -c
node js/tests/bigint-typeerror.js 2>&1 | od -c

Salida idéntica a Node (mismas excepciones con los mismos mensajes V8).

### completado
- [x] VM detecta mix BigInt/otro y lanza TypeError vía exception_handlers
- [x] Evaluator hace lo mismo para el path no-VM
- [x] Exponente negativo en `**` lanza RangeError
- [x] Error capturable por `try/catch` JS
- [x] Mensaje de error exacto coincide con V8 (Node)
- [x] División por cero (`1n / 0n`) → RangeError

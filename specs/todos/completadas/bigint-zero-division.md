# BigInt — División por cero (RangeError)

## status
completado

> Implementado originalmente como parte de `bigint-mix-typeerror.md` (el
> check de divisor cero en `div`/`mod_` se hace en el mismo bloque que
> el TypeError de mezcla de tipos). Este spec se conserva para trazabilidad
> y como test independiente (`js/tests/bigint-zero-div.js`).

## Problema
`1n / 0n` y `1n % 0n` deben lanzar `RangeError`, igual que `1 / 0`
(que retorna `Infinity`) lanza un error específico en operaciones
BigInt. Sin implementar, la división por cero con BigInt probablemente
crashea o devuelve basura.

## Contexto
ECMAScript define que la división BigInt por cero lanza `RangeError`
porque no hay representación para `Infinity` en BigInt (BigInt solo
puede representar enteros finitos).

```
1n / 0n   // RangeError: Division by zero
1n % 0n   // RangeError: Division by zero
0n / 0n   // RangeError: Division by zero
```

`Number / 0` retorna `Infinity` (no error), pero BigInt no puede
representar esto, así que es un error.

## Código que falla
```js
try { console.log(1n / 0n); } catch (e) { console.log("caught:", e); }
// Esperado: caught: RangeError: Division by zero
```

## Implementacion sugerida

### 1. VM (src/vm.zig)
En el opcode `div` y `mod_` para BigInt, antes de la operación,
verificar si el divisor es cero:

```zig
} else if (a == .big_int or b == .big_int) {
    // ... mix checks ...
    const right_big = ...;
    if ((op == .div or op == .mod_) and right_big.value.eqlZero()) {
        const err_msg = "RangeError: Division by zero";
        if (self.exception_handlers.items.len > 0) {
            // Push error y saltar a handler (mismo patrón que TypeError)
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
    // ... normal division logic
}
```

### 2. Evaluator (src/evaluator.zig)
Misma lógica para el path no-VM (modo `use_vm = false`):
```zig
if (op == .Divide or op == .Modulo) {
    if (right_big.value.eqlZero()) {
        env.throw_hit = true;
        env.throw_value = .{ .string = "RangeError: Division by zero" };
        return env.throw_value;
    }
}
```

### 3. Mensaje de error
V8 produce `"RangeError: Division by zero"`. Mantener el mismo
mensaje para paridad.

## Archivos de referencia
- src/vm.zig — `div`/`mod_` opcodes con BigInt
- src/evaluator.zig — `evaluateBinaryExpression` con BigInt
- src/vm.zig — `throw_stmt`/`exception_handlers` (mecanismo try/catch)

### JS Examples Complejos
```js
// División por cero
try { console.log(1n / 0n); }    catch (e) { console.log("caught:", e); }
try { console.log(0n / 0n); }    catch (e) { console.log("caught:", e); }
try { console.log(-1n / 0n); }   catch (e) { console.log("caught:", e); }

// Módulo por cero
try { console.log(1n % 0n); }    catch (e) { console.log("caught:", e); }
try { console.log(10n % 0n); }   catch (e) { console.log("caught:", e); }

// División normal no lanza
console.log(10n / 3n);    // 3n
console.log(10n % 3n);    // 1n
console.log(0n / 5n);     // 0n
console.log(0n % 5n);     // 0n

// Number (no BigInt) sigue retornando Infinity
console.log(1 / 0);       // Infinity
console.log(-1 / 0);      // -Infinity
console.log(0 / 0);       // NaN

// try/catch con BigInt division
try {
  const a = 100n;
  const b = 0n;
  const r = a / b;        // RangeError
} catch (e) {
  console.log("handled:", e);
}
```

### Vereficacion
- `1n / 0n` lanza `RangeError: Division by zero`
- `0n / 0n`, `-1n / 0n` también lanzan
- `1n % 0n`, `0n % 0n` también lanzan
- `10n / 3n` retorna `3n` (no error)
- `0n / 5n` retorna `0n`
- Capturable por `try/catch`
- Number division (no BigInt) no se ve afectada: `1/0` → `Infinity`
- Mensaje de error es "RangeError: Division by zero"

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/bigint-zero-div.js 2>&1 | od -c
node js/tests/bigint-zero-div.js 2>&1 | od -c

### completado
- [x] VM detecta divisor cero en `div`/`mod_` y lanza RangeError
- [x] Evaluator hace lo mismo
- [x] Mensaje exacto: "RangeError: Division by zero"
- [x] Capturable por `try/catch` JS

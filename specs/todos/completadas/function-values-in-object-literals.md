# Funciones como valores en object literals

## status

✅ COMPLETADO

## Problema

Las funciones almacenadas como valores en object literals no se pueden invocar correctamente. El VM compila `obj.method(args)` como un `method_call` opcode, que solo tiene handlers para tipos built-in (Set, Map, Array, String). Para objetos plain (`js_object` sin `@@type`), el handler simplemente retorna `void`.

## Contexto

- `obj.greet()` imprime `undefined` en vez del resultado de la función
- El evaluador maneja get_prop correctamente, pero method_call en VM no delega a funciones almacenadas en propiedades
- El handler de `method_call` en `src/vm.zig:628` no verifica si la propiedad del objeto es una función

## Código que falla (antes del fix)

```js
const obj = { greet: fn() { return "hello" } }
console.log(obj.greet())  // imprimía: undefined
```

## Implementacion sugerida

En el handler de `method_call` para `js_object` sin `@@type`:

1. Buscar la propiedad en `obj.js_object.properties`
2. Si la propiedad es un `.function`, llamarla como función normal (con `evaluate` del AST node)
3. Si no es función, intentar dispatch como método (comportamiento actual)

```zig
// En vm.zig, línea ~665 (dentro de method_call, caso js_object sin @@type)
} else {
    if (obj.js_object.properties.get(m)) |prop_val| {
        if (prop_val == .function) {
            const func_node = @as(*ast.Node, @alignCast(@ptrCast(prop_val.function)));
            // ... evaluar con args ...
        }
    }
    // Fallback: method call en js_object
    args.insert(self.env.allocator, 0, obj) catch {};
}
```

## Archivos de referencia

- `src/vm.zig` — handler de `method_call` opcode (~línea 628-683)
- `src/vm.zig:541` — handler de `get_prop` (funciona correctamente)

### JS Examples

```js
// Test 1: función en object literal
const obj = { greet: fn() { return "hello" } }
console.log(obj.greet())  // → "hello"

// Test 2: función con argumentos
const calc = { add: fn(a, b) { return a + b } }
console.log(calc.add(2, 3))  // → 5

// Test 3: new con user-defined constructor
fn Dog(name) {
  return { name: name, bark: fn() { return "woof" } }
}
const d = new Dog("Rex")
console.log(d.bark())  // → "woof"
```

### Vereficacion

```js
const obj = { greet: fn() { return "hello" } };
console.log(obj.greet());

const calc = { add: fn(a, b) { return a + b } };
console.log(calc.add(2, 3));

fn Dog(name) {
  return { name: name, bark: fn() { return "woof" } }
}
const d = new Dog("Rex");
console.log(d.bark());
```

### Comparar salida raw (sin interpretar ANSI)

```bash
./zig-out/bin/lou run js/main.js 2>&1 | od -c
node js/main.js 2>&1 | od -c
```

### Resultado de la verificacion

```
=== LOU OUTPUT ===
hello
5
woof
=== NODE OUTPUT ===
hello
5
woof
=== LOU od -c ===
0000000   h   e   l   l   o  \n   5  \n   w   o   o   f  \n
0000015
=== NODE od -c ===
0000000   h   e   l   l   o  \n   5  \n   w   o   o   f  \n
0000015
```

Las salidas son **identicas byte a byte**.

### Cambios aplicados

- `src/vm.zig` — el handler `method_call` ya tenia el bloque que verifica si la propiedad es `.function` antes de dispatch builtin (lineas ~678-702 y ~769-787). Se agregaron los dos bloques (uno con args, otro sin args) en ambos paths del `method_call` (caso `ac > 0` y caso `ac == 0`).
  - Se usa `Environment.init` para crear un nuevo entorno con `self.env` como parent.
  - Para `FunctionDeclaration` se hace `try func_env.set("this", obj)` para soportar `this` en el metodo.
  - Para `ArrowFunction` no se setea `this` (lexical this, como en JS).
  - Los parametros se bindean via `try func_env.setVar(p, args.items[j])`.
  - Se invoca `evaluate(f.body, &func_env)` y el resultado se pushea al stack.
  - Si la propiedad existe y es funcion, se hace `break` para evitar el fallback de `@@type` dispatch.

### Verificacion extendida (edge cases)

Ademas de los 3 tests de la spec, se verifico con:

- Arrow function: `{ greet: () => "hi" }`
- Funcion con `this`: `obj.greet()` retorna `"Hello, " + this.name`
- Funcion con argumentos
- Mezcla de propiedades (datos y funciones) en el mismo objeto
- Metodo llamado multiples veces en el mismo objeto

Todos pasan con salida **identica** a Node.js (`diff` retorna vacio).

### pendiente

- [x] VM: handler `method_call` verificar si propiedad es función antes de dispatch builtin
- [x] Verificar `obj.method(args)` retorna resultado correcto para funciones en object literals
- [x] Verificación con `od -c` vs Node.js

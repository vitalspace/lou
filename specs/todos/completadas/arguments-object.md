# arguments object en funciones

## status

IMPLEMENTED

## Problema

Las funciones regulares (no arrow) no tienen acceso al objeto `arguments`. ECMAScript requiere que `arguments` esté disponible en el scope de funciones regulares con todos los argumentos pasados.

## Contexto

ECMAScript 9.2.10 FunctionDeclarationInstantiation: crea el objeto `arguments` para funciones regulares (no arrow, no strict).

## Código que falla

```js
function sum() {
    var total = 0;
    for (var i = 0; i < arguments.length; i++) {
        total += arguments[i];
    }
    return total;
}
console.log(sum(1, 2, 3)); // Debería: 6, Actual: error (arguments no definido)
```

## Implementacion sugerida

En la creación del environment de funciones regulares:

```zig
// In invokeFunctionNode / callFuncNode:
if (is_regular_function and not is_strict) {
    // Create arguments object
    var args_obj = ObjectValue.init();
    args_obj.set("length", Value.integer(args.len));
    for (args, 0..) |arg, i| {
        args_obj.set(intToString(i), arg);
    }
    func_env.set("arguments", Value{ .js_object = args_obj });
}
```

## Archivos de referencia

- `src/evaluator.zig:2837` — `invokeFunctionNode`
- `src/vm.zig:972` — `callFuncNode`
- ECMAScript 9.2.10 FunctionDeclarationInstantiation

### JS Examples Complejos

```js
// Variadic function
function logger() {
    for (var i = 0; i < arguments.length; i++) {
        console.log(arguments[i]);
    }
}
logger("a", "b", "c");

// arguments as array
function toArray() {
    return Array.from(arguments);
}
var arr = toArray(1, 2, 3); // [1, 2, 3]

// Named params + arguments
function mixed(a, b) {
    console.log(a, b);          // 1, 2
    console.log(arguments[2]);  // 3
}
mixed(1, 2, 3);
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-arguments.js
node js/test-arguments.js
```

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/main.js 2>&1 | od -c
node js/main.js 2>&1 | od -c

### pendiente

COMPLETED:
- [x] arguments object in regular functions
- [x] arguments.length
- [x] arguments[i] indexing
- [x] arguments[0] = val modification (set_index)
- [x] arguments.callee
- [x] Arguments-param binding (sloppy mode)
- [x] Arrow functions inherit arguments from outer scope

# Arrow functions: captura de this

## status

NOT IMPLEMENTED

## Problema

Las arrow functions no capturan `this` del scope léxico. En `evaluator.zig:2868-2876`, el `this_val` se ignora para arrow functions. ECMAScript requiere que las arrow functions hereden `this` del scope que las contiene.

## Contexto

ECMAScript 15.3.5: Arrow functions no tienen su propio `this`. Usan el `this` del enclosing lexical scope. Esto es fundamental para callbacks en métodos.

## Código que falla

```js
var obj = {
    name: "Alice",
    greet: function() {
        var fn = () => {
            console.log(this.name); // Debería: "Alice", Actual: undefined
        };
        fn();
    }
};
obj.greet();
```

## Implementacion sugerida

En `evaluator.zig:2868-2876`, cuando se evalúa una `ArrowFunction`, propagar el `this` del environment:

```zig
// ArrowFunction should inherit this from enclosing scope
if (node.type == .ArrowFunction) {
    // Use the this_val from the enclosing function, don't create a new one
    func_env.this_val = env.this_val;
} else {
    // Regular functions get this_val as parameter
    func_env.this_val = this_val;
}
```

## Archivos de referencia

- `src/evaluator.zig:2868-2876` — `invokeFunctionNode`
- `src/vm.zig:972` — `callFuncNode`
- ECMAScript 15.3.5 `[[Call]]`

### JS Examples Complejos

```js
// Method with arrow callback
var counter = {
    count: 0,
    start: function() {
        var inc = () => { this.count++; };
        inc();
        inc();
        console.log(this.count); // 2
    }
};
counter.start();

// Nested arrows
var obj = {
    value: 42,
    method: function() {
        var fn1 = () => {
            var fn2 = () => {
                console.log(this.value); // 42
            };
            fn2();
        };
        fn1();
    }
};
obj.method();
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-arrow-this.js
node js/test-arrow-this.js
```

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/main.js 2>&1 | od -c
node js/main.js 2>&1 | od -c

### pendiente

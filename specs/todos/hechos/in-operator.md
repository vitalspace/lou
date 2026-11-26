# Operador in

## status

**completado** — 2026-11-26 (compat: 73 PASS / 12 FAIL / 1 SKIP)

`tests/compat/in-operator.{js,lou}` produce salida byte-idéntica a Node.

## Problema

En el VM, `a in b` compilaba como una expresión binaria genérica cuyo
`switch` no tenía rama para `.In`: se evaluaban ambos operandos y se dejaban
en la pila, sin resultado. La siguiente llamada a método encontraba un tipo
inesperado y abortaba con `error: Thrown` (`throwTypeError`). El evaluador AST
ya tenía una implementación básica, pero el camino del VM nunca la usaba.

## Implementación

### VM (`src/vm.zig`)

`.In` y `.InstanceOf` se compilan con `eval_node` sobre el nodo completo:
la introspección de propiedades/prototipos vive en el evaluador. Antes caían
en `else => {}` dentro del `switch` de operadores binarios.

### Evaluador (`src/evaluator.zig`)

- `In` coacciona el operando izquierdo a clave (`string`, entero, float,
  booleano, símbolo).
- `js_object`: recorre la cadena de prototipos (`properties` + `prototype`),
  no solo las propiedades propias.
- `array`: `"length" in []` es `true`; los índices usan `arrayKeyIndex`,
  que exige dígitos decimales canónicos (sin ceros a la izquierda), y
  descartan huecos (`0 in [,]` es `false`).
- Los literales de objeto del evaluador ahora enlazan
  `env.object_prototype`, igual que `make_object` en el VM, para que
  `"toString" in {}` sea `true`.

## Verificación

```bash
diff <(./zig-out/bin/lou run tests/compat/in-operator.lou) \
     <(node tests/compat/in-operator.js)
# sin diferencias
```

Casos extra comprobados contra Node: propiedades heredadas (`toString`,
`hasOwnProperty`), huecos, `"01" in [1,2]`, `"1.0" in [1]`, `length`.

Tests unitarios en `src/evaluator.zig`: `in operator - own properties, arrays
and holes`.

## Limitaciones

- `in` sobre objetos builtin (`.object`) o funciones no está implementado
  (devuelve `false`).
- El operando derecho primitivo no lanza `TypeError` como en JS; los casos
  no-objeto devuelven `false` (las cadenas solo admiten índices).
- `in` con claves numéricas más allá de `usize` devuelve `false`.

## Referencias

- `src/vm.zig` — compilación de `.In`/`.InstanceOf`
- `src/evaluator.zig` — rama `.In`, `arrayKeyIndex`, literales de objeto
- `tests/compat/in-operator.{js,lou}`
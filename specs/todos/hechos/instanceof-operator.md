# Operador instanceof

## status

**completado** — 2026-11-26 (compat: 73 PASS / 12 FAIL / 1 SKIP)

`tests/compat/instanceof-operator.{js,lou}` produce salida byte-idéntica a Node.

## Problema

Igual que `in`: el VM no tenía rama para `.InstanceOf`, así que evaluaba los
dos operandos y los dejaba en la pila. El resultado era un `error: Thrown` en
la siguiente llamada a método (por ejemplo `console.log`).

## Implementación

### VM (`src/vm.zig`)

`.InstanceOf` se compila con `eval_node`, delegando en el evaluador AST.

### Evaluador (`src/evaluator.zig`)

- Primitivos (`string`, `number`, `bigint`, `boolean`, `null`, `undefined`)
  devuelven `false` inmediatamente.
- El constructor derecho se identifica por `BuiltinObjectImpl.name`.
- `array` es `instanceof Array` y `instanceof Object`.
- `js_object` con `@@type` (p. ej. `Date`) coincide con ese nombre;
  `@@subtype` cubre `SyntaxError`, `TypeError`, etc.; el resto de objetos
  planos coincide con `Object`.
- `generator`/`iterator`/`function`/`closure` no coinciden con builtins.

## Verificación

```bash
diff <(./zig-out/bin/lou run tests/compat/instanceof-operator.lou) \
     <(node tests/compat/instanceof-operator.js)
# sin diferencias
```

El fixture cubre builtins, primitivos, `null`/`undefined` y negación.

Tests unitarios en `src/evaluator.zig`: `instanceof operator - builtins and
primitives`.

## Efecto colateral positivo

Al arreglar ambos operadores también pasaron `error-objects`,
`finalization-registry` y `for-var-no-init`, que los usaban internamente.

## Limitaciones

- Constructores definidos por el usuario (`function Foo(){}` + `new Foo()`)
  no se resuelven por prototipo.
- `instanceof` con `Symbol.hasInstance` no está soportado.

## Referencias

- `src/vm.zig` — compilación de `.InstanceOf`
- `src/evaluator.zig` — rama `.InstanceOf`
- `tests/compat/instanceof-operator.{js,lou}`
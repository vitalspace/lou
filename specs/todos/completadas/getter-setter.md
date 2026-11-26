# Getter / setter

## status

**completado** — 2026-11-26 (compat: 76 PASS / 9 FAIL / 1 SKIP)

`tests/compat/getter-setter.{js,lou}` produce salida byte-idéntica a Node.

## Problema

El parser de literales de objeto exigía `:` después de cada clave, así que
`{ get value() { ... } }` fallaba con `ExpectedColon`. El AST ya tenía
`PropertyKind { init, get, set }`, pero nada lo producía ni lo consumía.

## Implementación

- `src/parser.zig`: tras consumir una clave `get`/`set`, si el siguiente token
  no es `:`, parsea `nombre ( params ) { cuerpo }` y crea una propiedad
  `.get`/`.set` cuyo valor es un `FunctionDeclaration` anónimo. `{ get: 1 }`
  sigue siendo una propiedad normal llamada `get`.
- `src/evaluator.zig`: al construir el literal, cada acceso se guarda en un
  objeto envoltorio `@@native="Accessor"` con las claves `get` y/o `set`; la
  propiedad real del objeto apunta a ese envoltorio (visible para
  `hasOwnProperty`, `Object.keys`, etc.).
- Lectura (`MemberAccess`, `ArrayIndex` y `get_prop` del VM): si el valor es
  un acceso, invoca el getter con `this` = objeto receptor.
- Escritura (`PropertySet`, asignación a miembro/índice y `set_prop` del VM):
  si hay setter, lo invoca con `this` = objeto receptor y el valor asignado.
- `src/vm.zig`: los literales con accesos se difieren a `eval_node` (el
  compilador no puede emitir las funciones como valores con `make_object`).
- `MemberAccess` del evaluador ahora también resuelve miembros de objetos
  builtin (`Math.PI`), necesario al ejecutar el cuerpo del getter.

## Verificación

```bash
diff <(./zig-out/bin/lou run tests/compat/getter-setter.lou) \
     <(node tests/compat/getter-setter.js)
# sin diferencias
```

El fixture cubre get/set básicos, getter de solo lectura, conversión
Fahrenheit/Celsius, getter calculado y setter con efectos secundarios.

Test unitario en `src/evaluator.zig`: `object literal getters and setters`
(setter duplica, getter lee `this._v`).

## Limitaciones

- Solo claves literales: `get [expr]() {}` no está soportado.
- No hay `Object.defineProperty` ni descriptores; el envoltorio es interno.
- `JSON.stringify`/spread copian el envoltorio, no invocan el getter.
- Asignar a un getter sin setter se ignora silenciosamente (JS estricto
  lanzaría TypeError).

## Referencias

- `src/ast.zig` (`PropertyKind`, `Property.kind`)
- `src/parser.zig` (`parseObjectLiteral`)
- `src/evaluator.zig` (`ObjectLiteral`, `MemberAccess`, `setAccessorProperty`)
- `src/vm.zig` (`pushProperty`, `set_prop`, `findAccessorValue`)
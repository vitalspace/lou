# Profiler — Benchmarking Lou vs Node

**Prioridad: baja**

## Problema

No hay forma automatizada de medir y comparar el rendimiento de Lou contra Node.js.

## Contexto

- Spec existente en `specs/tools/profiler.md` (152 líneas con diseño completo)
- Es un CLI independiente en Zig (no modifica Lou)
- Usa `time`, `perf`, `valgrind` como backends
- Genera reportes comparativos

## Referencia

- `specs/tools/profiler.md`

## Verificación

### Código JavaScript a verificar

```js
// benchmark-simple.js
fn fib(n) {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

console.time("fib");
fib(30);
console.timeEnd("fib");
```

### Cómo correr y verificar

1. **Archivo de prueba**: `js/benchmark-simple.js`

2. **Ejecutar con Lou (Zig)**:
```bash
time zig build run -- run js/benchmark-simple.js
```

3. **Ejecutar con Node.js**:
```bash
time node js/benchmark-simple.js
```

4. **Esperado**: El profiler CLI (futuro) generará reporte comparativo con tiempos de ambos runtimes.

5. **Implementación requerida**: CLI independiente en Zig que:
   - Compile Lou
   - Ejecute script con `time -f "%e %M"`
   - Ejecute script con Node
   - Genere reporte CSV o markdown

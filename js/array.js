console.time("total");

// === PUSH + LENGTH ===
var productos = [];
productos.push("manzana");
productos.push("naranja", "plátano");
console.log(productos.length); // 3

// === AT ===
console.log(productos.at(0)); // "manzana"
console.log(productos.at(-1)); // "plátano"

// === CONCAT ===
var frutas2 = ["uva", "fresa"];
var todas = productos.concat(frutas2);
console.log(todas.length); // 5
console.log(todas.at(3)); // "uva"

var conExtra = productos.concat("mango", ["kiwi", "pera"]);
console.log(conExtra.length); // 6

// === COPY WITHIN ===
var letras = ["a", "b", "c", "d", "e"];
console.log(letras.copyWithin(0, 3, 4)); // ["d", "b", "c", "d", "e"]

var arr2 = [1, 2, 3, 4, 5];
console.log(arr2.copyWithin(-2, -3, -1)); // [1, 2, 3, 3, 4]

// === ENTRIES ===
var nums = [10, 20, 30];
var it = nums.entries();
console.log(it.next().value); // [0, 10]
console.log(it.next().value); // [1, 20]
console.log(it.next().value); // [2, 30]
console.log(it.next().value); // undefined

// === EVERY ===
function mayorQueDiez(v) {
  return v > 10;
}
console.log([12, 5, 8].every(mayorQueDiez)); // false
console.log([15, 20, 30].every(mayorQueDiez)); // true

// === FILL ===
console.log([1, 2, 3].fill(4)); // [4, 4, 4]
console.log([1, 2, 3].fill(4, 1, 2)); // [1, 4, 3]
console.log(Array(3).fill(0)); // [0, 0, 0]

// === FILTER ===
var precios = [12, 5, 8, 130, 44];
function esGrande(v) {
  return v >= 10;
}
console.log(precios.filter(esGrande)); // [12, 130, 44]

// === FIND ===
function mayorQue100(v) {
  return v > 100;
}
console.log([5, 12, 8, 130, 44].find(mayorQue100)); // 130

// === FINDINDEX ===
console.log([5, 12, 8, 130, 44].findIndex(mayorQue100)); // 3
console.log([1, 2, 3].findIndex(mayorQue100)); // -1

// === FINDLAST ===
function mayorQue45(v) {
  return v > 45;
}
console.log([5, 12, 50, 130, 44].findLast(mayorQue45)); // 130

// === FINDLASTINDEX ===
console.log([5, 12, 50, 130, 44].findLastIndex(mayorQue45)); // 3
console.log([1, 2, 3].findLastIndex(mayorQue45)); // -1

// === POP ===
var copia = ["x", "y", "z"];
console.log(copia.pop()); // "z"
console.log(copia.length); // 2

// === EJEMPLO INTEGRADO: Análisis de ventas ===
var ventas = [150, 200, 80, 300, 45, 120, 95];
console.log(ventas.length); // 7
console.log(ventas.at(0)); // 150
console.log(ventas.at(-1)); // 95
console.log(
  ventas.every(function (v) {
    return v > 50;
  }),
); // true
console.log(
  ventas.filter(function (v) {
    return v > 100;
  }),
); // [150, 200, 300, 120]
console.log(
  ventas.find(function (v) {
    return v > 250;
  }),
); // 300
console.log(
  ventas.findIndex(function (v) {
    return v > 250;
  }),
); // 3
console.log(
  ventas.findLast(function (v) {
    return v > 100;
  }),
); // 120
console.log(
  ventas.findLastIndex(function (v) {
    return v > 100;
  }),
); // 5

var copiaVentas = ventas.concat();
console.log(copiaVentas.pop()); // 95
console.log(copiaVentas.length); // 6

var buffer = [0, 0, 0, 0];
console.log(buffer.fill(1)); // [1, 1, 1, 1]

var top3 = [ventas.at(0), ventas.at(1), ventas.at(2)];
var it2 = top3.entries();
console.log(it2.next().value); // [0, 150]
console.log(it2.next().value); // [1, 200]
console.log(it2.next().value); // [2, 80]

// === CHAINED: filter + findLastIndex ===
var nums = [3, -1, 1, 4, 1, 5, 9, 2, 6];
var lastTrough = nums
  .filter((num) => num > 0)
  .findLastIndex((num, idx, arr) => {
    if (idx > 0 && num >= arr[idx - 1]) return false;
    if (idx < arr.length - 1 && num >= arr[idx + 1]) return false;
    return true;
  });
console.log(lastTrough); // 6

// === FLAT: consolidar ventas por categoría ===
var ventasPorDia = [
  [150, 200, 80],
  [300, 45],
  [120, 95, 210, 60],
];
var todasLasVentas = ventasPorDia.flat();
console.log(todasLasVentas); // [150, 200, 80, 300, 45, 120, 95, 210, 60]
console.log(todasLasVentas.length); // 9

// === FLATMAP ===
var duplicado = [1, 2, 3, 4].flatMap((x) => [x, x * 2]);
console.log(duplicado); // [1, 2, 2, 4, 3, 6, 4, 8]

// FlatMap como map (retorna no-array)
var por10 = [1, 2, 3].flatMap((x) => x * 10);
console.log(por10); // [10, 20, 30]

// FlatMap vacío
console.log([].flatMap((x) => [x])); // []

// === FLATMAP: desglosar ventas en registros individuales ===
var pedidos = [
  { id: 1, items: ["laptop", "mouse"] },
  { id: 2, items: ["teclado"] },
  { id: 3, items: ["monitor", "cable"] },
];
var todosItems = pedidos.flatMap((p) => p.items);
console.log(todosItems); // ["laptop", "mouse", "teclado", "monitor", "cable"]

// === FOREACH ===
var letras2 = ["a", "b", "c"];
function logElemento(v) {
  console.log(v);
}
letras2.forEach(logElemento); // "a", "b", "c"

// === ARRAY.FROM ===
console.log(Array.from("foo")); // ["f", "o", "o"]
console.log(Array.from([1, 2, 3], (x) => x + x)); // [2, 4, 6]

// === ARRAY.ISARRAY ===
console.log(Array.isArray([1, 2, 3])); // true
console.log(Array.isArray({ length: 3 })); // false

// === INCLUDES ===
console.log([1, 2, 3].includes(2)); // true
console.log([1, 2, 3].includes(4)); // false
console.log(["cat", "dog", "bat"].includes("at")); // false

// === INDEXOF ===
var bestias = ["ant", "bison", "camel", "duck", "bison"];
console.log(bestias.indexOf("bison")); // 1
console.log(bestias.indexOf("bison", 2)); // 4
console.log(bestias.indexOf("giraffe")); // -1

// === JOIN ===
var elementos = ["Fuego", "Aire", "Agua"];
console.log(elementos.join()); // "Fuego,Aire,Agua"
console.log(elementos.join(", ")); // "Fuego, Aire, Agua"
console.log(elementos.join(" + ")); // "Fuego + Aire + Agua"
console.log(elementos.join("")); // "FuegoAireAgua"

// === KEYS ===
var keysArr = ["a", "b", "c"];
var keyIt = keysArr.keys();
console.log(keyIt.next().value); // 0
console.log(keyIt.next().value); // 1
console.log(keyIt.next().value); // 2
console.log(keyIt.next().value); // undefined

// Keys — usando .done
var keyDone = ["x"].keys();
console.log(keyDone.next().done); // false
console.log(keyDone.next().done); // true

// === LASTINDEXOF ===
var animales = ["Dodo", "Tigre", "Pingüino", "Dodo"];
console.log(animales.lastIndexOf("Dodo")); // 3
console.log(animales.lastIndexOf("Dodo", 2)); // 0
console.log(animales.lastIndexOf("Jirafa")); // -1

var nums = [1, 2, 3, 2, 1];
console.log(nums.lastIndexOf(2)); // 3
console.log(nums.lastIndexOf(2, 2)); // 1

// === MAP ===
var cuadrados = [1, 4, 9, 16].map((x) => x * 2);
console.log(cuadrados); // [2, 8, 18, 32]

var mayusculas = ["a", "b", "c"].map((x) => x.toUpperCase());
console.log(mayusculas); // ["A", "B", "C"]

var conIndice = [10, 20, 30].map((v, i) => v + i);
console.log(conIndice); // [10, 21, 32]

// Map vacío
console.log([].map((x) => x * 2)); // []

// === REDUCE ===
var suma = [1, 2, 3, 4].reduce((acc, v) => acc + v, 0);
console.log(suma); // 10

// Reduce sin valor inicial
console.log([1, 2, 3, 4].reduce((acc, v) => acc + v)); // 10

// Reduce vacío con valor inicial
console.log([].reduce((acc, v) => acc + v, 0)); // 0

// Reduce con índice
console.log([1, 2, 3].reduce((acc, v, i) => acc + v + i, 0)); // 9

// === EJEMPLO INTEGRADO: Procesamiento de inventario ===
var inventario = [
  { producto: "laptop", precio: 15000, cantidad: 3 },
  { producto: "mouse", precio: 200, cantidad: 15 },
  { producto: "teclado", precio: 800, cantidad: 8 },
  { producto: "monitor", precio: 4000, cantidad: 2 },
];

// Map: obtener lista de nombres
var nombres = inventario.map((item) => item.producto);
console.log(nombres); // ["laptop", "mouse", "teclado", "monitor"]

// Map: calcular valor total por producto
var valores = inventario.map((item) => item.precio * item.cantidad);
console.log(valores); // [45000, 3000, 6400, 8000]

// Reduce: valor total del inventario
var totalInventario = valores.reduce((acc, v) => acc + v, 0);
console.log(totalInventario); // 62400

// Join: productos como string
console.log(nombres.join(" | ")); // "laptop | mouse | teclado | monitor"

// Keys: iterar sobre índices
var itKeys = nombres.keys();
console.log(itKeys.next().value); // 0
console.log(itKeys.next().value); // 1
console.log(itKeys.next().value); // 2
console.log(itKeys.next().value); // 3

// lastIndexOf: buscar producto duplicado
var conDup = ["laptop", "mouse", "laptop", "teclado"];
console.log(conDup.lastIndexOf("laptop")); // 2
console.log(conDup.lastIndexOf("laptop", 1)); // 0
console.timeEnd("total");

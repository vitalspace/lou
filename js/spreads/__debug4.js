console.log("=== 4. SET SPREAD ===");

var s = Set([10, 20, 30]);
console.log([...s]);

var setVacio = Set([]);
console.log([...setVacio]);

var letras = Set(['x', 'y', 'z']);
console.log([...letras]);

var setUnico = Set([1, 1, 2, 2, 3]);
console.log([...setUnico]);

console.log("=== 5. MAP SPREAD ===");

var m = Map([['a', 1], ['b', 2]]);
console.log([...m]);

var mapVacio = Map([]);
console.log([...mapVacio]);

var mapMulti = Map([[1, 'one'], [2, 'two'], [3, 'three']]);
console.log([...mapMulti]);

console.log("=== END ===");

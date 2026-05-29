console.log("=== 6. METHOD CALL SPREAD ===");

var arrPush = [1, 2, 3];
console.log(arrPush.push(...[4, 5]));
console.log(arrPush);

var arrUnshift = [3, 4, 5];
console.log(arrUnshift.unshift(...[1, 2]));
console.log(arrUnshift);

var arrConcat = [1, 2];
var concatResult = arrConcat.concat(...[[3, 4], [5, 6]]);
console.log(concatResult);

var arrIncludes = [10, 20, 30, 40];
console.log(arrIncludes.includes(...[20]));
console.log(arrIncludes.indexOf(...[30]));

var arrChain = [];
console.log(arrChain.push(...[1, 2, 3]));
console.log(arrChain.pop());
console.log(arrChain.length);

var str = "hello";
console.log(str.includes(...["ell"]));
console.log(str.indexOf(...["l"]));
console.log(str.startsWith(...["he"]));
console.log(str.endsWith(...["lo"]));

var arrSlice = [0, 1, 2, 3, 4, 5];
var sliced = arrSlice.slice(...[1, 4]);
var arrSliceDest = [];
arrSliceDest.push(...sliced);
console.log(arrSliceDest);

console.log("=== 7. ARROW FUNCTION SPREAD ===");

var add3 = (a, b, c) => a + b + c;
console.log(add3(...[10, 20, 30]));
console.log(add3(...[1, 2, 3, 4, 5]));

var double = (x) => x * 2;
console.log(double(...[21]));

console.log("=== END ===");

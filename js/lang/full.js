console.time("build");

var sum = 0;
for (let i = 0; i < 1000000000; i = i + 1) {
  sum = sum + i;
}
console.log(sum);

var arr = [0, 1, 2, 3, 4];
console.log(arr.length);

arr.push(5);
console.log(arr[4]);

const PI = 3.14159;
console.log(PI);

var greeting = "hello world";
console.log(greeting);

var flag = true;
console.log(flag);

console.log(Math.abs(-42));

function add(a, b) {
  return a + b;
}
console.log(add(10, 20));

var double = (x) => x * 2;
console.log(double(5));

// --- let (block-scoped) vs var ---
var x = 1;
{
  let x = 2;
  console.log(x);
}
console.log(x);

// --- if / else ---
var n = 10;
if (n > 5) {
  console.log("big");
} else {
  console.log("small");
}

// --- while loop ---
var w = 0;
var wsum = 0;
while (w < 5) {
  wsum += w;
  w++;
}
console.log(wsum);

// --- compound assignment ---
var c = 10;
c += 5;
console.log(c);
c -= 3;
console.log(c);
c *= 2;
console.log(c);
c %= 7;
console.log(c);

// --- comparison & logical ---
console.log(5 == 5);
console.log(5 === 5);
console.log(3 != 4);
console.log(3 !== 4);
console.log(2 < 3);
console.log(3 <= 3);
console.log(4 > 1);
console.log(4 >= 4);
console.log(true && true);
console.log(false || true);
console.log(!false);

// --- bitwise ---
console.log(5 & 3);
console.log(5 | 3);
console.log(5 ^ 3);
console.log(~0);
console.log(1 << 3);
console.log(8 >> 1);

// --- nullish coalescing ---
var nothing = null;
console.log(nothing ?? 42);
console.log(10 ?? 99);

// --- increment / decrement ---
var inc = 0;
inc++;
console.log(inc);
++inc;
console.log(inc);
inc--;
console.log(inc);

// --- array pop ---
var pops = [10, 20, 30];
var last = pops.pop();
console.log(last);
console.log(pops.length);

// --- string concatenation ---
var hello = "hello";
var world = " world";
console.log(hello + world);

// --- template string ---
console.log(`hello from lou`);

// --- console.error ---
console.error("this is an error");

// --- null / undefined ---
var nada = null;
var undef = undefined;
console.log(nada);
console.log(undef);

// --- multi-line comment ---
/* this is a
   multi-line comment */
var after_comment = 99;
console.log(after_comment);

// --- 3x3 matrix with nested for loops ---
var matrix = [[], [], []];
for (let i = 0; i < 3; i = i + 1) {
  for (let j = 0; j < 3; j = j + 1) {
    matrix[i].push(i * 3 + j + 1);
  }
}
console.log(matrix[0]);
console.log(matrix[1]);
console.log(matrix[2]);

// --- predefined 3x3 matrix ---

// alv padrino

const predefined = [
  [1, 2, 3],
  [4, 5, 6],
  [7, 8, 9],
];
for (let i = 0; i < predefined.length; i = i + 1) {
  for (let j = 0; j < predefined[i].length; j = j + 1) {
    console.log("matrix[" + i + "][" + j + "] = " + predefined[i][j]);
  }
}

console.timeEnd("build");
// While loop
var i = 0;
var sum = 0;
while (i < 5) {
    sum = sum + i;
    i = i + 1;
}
console.log(sum);

// For loop with var
var total = 0;
for (var j = 1; j < 6; j = j + 1) {
    total = total + j;
}
console.log(total);

// For loop with let (block scoped)
var sum2 = 0;
for (let k = 0; k < 5; k = k + 1) {
    sum2 = sum2 + k;
}
console.log(sum2);

// Nested loops
var result = 0;
var a = 0;
while (a < 3) {
    var b = 0;
    while (b < 3) {
        result = result + 1;
        b = b + 1;
    }
    a = a + 1;
}
console.log(result);

// Performance test: sum from 0 to 999
console.time("loop");
var big = 0;
for (let i = 0; i < 100000000; i = i + 1) {
    big = big + i;
}
console.log(big);
console.timeEnd("loop");

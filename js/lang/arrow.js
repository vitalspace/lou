// Arrow functions
const double = (x) => x * 2;
console.log(double(5));
console.log(double(0));

const add2 = (a, b) => a + b;
console.log(add2(10, 20));
console.log(add2(-5, 5));

// Arrow with block body
const max2 = (a, b) => {
    if (a > b) {
        return a;
    }
    return b;
};
console.log(max2(100, 50));
console.log(max2(3, 7));

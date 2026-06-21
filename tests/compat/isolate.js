const obj1 = {
    a: function() { return 1; },
    b: function() { return 2; }
};
console.log(typeof obj1.a);
console.log(typeof obj1.b);
console.log(obj1.a());
console.log(obj1.b());

console.log("---");

const obj2 = {
    val: 99,
    getVal: function() { return this.val; }
};
console.log(obj2.getVal());

console.log("---");

const arr = [1, 2, 3];
const doubled = arr.map(function(x) { return x * 2; });
console.log(doubled);

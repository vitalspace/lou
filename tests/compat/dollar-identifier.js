// $ in identifiers

var $x = 1;
console.log($x);

var $$ = 2;
console.log($$);

var $0 = 3;
console.log($0);

var $_ = 4;
console.log($_);

let $arr = [10, 20, 30];
console.log($arr[0], $arr[1], $arr[2]);

// $ as function parameter
const double = ($n) => $n * 2;
console.log(double(5));

// $ in object property
const obj = { $prop: 42 };
console.log(obj.$prop);

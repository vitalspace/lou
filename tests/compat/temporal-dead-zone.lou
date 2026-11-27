function show(label, fn) {
  try { fn(); console.log(label + ": no error"); } catch (e) { console.log(label + ": " + e.name + ": " + e.message); }
}
show("top", function () { console.log(x); });
let x = 5;
console.log("x=" + x);
show("block", function () { { console.log(y); const y = 10; } });
function inner() { console.log(z); let z = 2; return z; }
show("function", inner);
show("self", function () { let a = a; });
show("typeof", function () { console.log(typeof q); let q = 1; });
let shadow = 1;
show("shadow", function () { { console.log(shadow); let shadow = 2; } });
for (let i = 0; i < 2; i++) { let i = 100; console.log(i); }
let arrow = () => { console.log(late); let late = 3; };
try { arrow(); } catch (e) { console.log("arrow: " + e.name); }
console.log("done");

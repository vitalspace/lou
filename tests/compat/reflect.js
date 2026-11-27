const obj = { a: 1 };
console.log(Reflect.get(obj, "a"), Reflect.get(obj, "z"));
console.log(Reflect.set(obj, "b", 2), obj.b);
console.log(Reflect.has(obj, "a"), Reflect.has(obj, "z"));
console.log(Reflect.deleteProperty(obj, "b"), obj.b);
console.log(Reflect.ownKeys({ x: 1, y: 2 }).join(","));
function add(a, b) { return a + b; }
console.log(Reflect.apply(add, null, [2, 3]));
function Point(x, y) { this.x = x; this.y = y; }
const p = Reflect.construct(Point, [4, 5]);
console.log(p.x, p.y);
const proto = { greet: function () { return "hi"; } };
const o2 = {};
console.log(Reflect.setPrototypeOf(o2, proto), Reflect.getPrototypeOf(o2) === proto, o2.greet());
console.log(Reflect.isExtensible(obj));
console.log(Reflect.defineProperty(obj, "c", { value: 3 }), obj.c);
const d = Reflect.getOwnPropertyDescriptor(obj, "c");
console.log(d.value);
console.log(Reflect.preventExtensions(obj), Reflect.isExtensible(obj));
console.log(Reflect.get([10, 20], "0"));
try { Reflect.get(1, "x"); } catch (e) { console.log(e.name, e.message); }
try { Reflect.ownKeys("x"); } catch (e) { console.log(e.name, e.message); }

// WeakMap/WeakSet: object-only keys, identity semantics, no enumerable API.
const key = { id: 1 };
const wm = new WeakMap();
wm.set(key, "a");
console.log(wm.get(key));
console.log(wm.has(key));
console.log(wm.has({ id: 1 }));
console.log(wm.delete(key));
console.log(wm.has(key));

const initialized = new WeakMap([[key, 5]]);
console.log(initialized.get(key));

try { wm.set("primitive", 1); } catch (e) { console.log(e instanceof TypeError, e.message); }

const item = { name: "x" };
const ws = new WeakSet();
ws.add(item);
console.log(ws.has(item));
console.log(ws.delete(item));
console.log(ws.has(item));

const ws2 = new WeakSet([item]);
console.log(ws2.has(item));

try { ws2.add(42); } catch (e) { console.log(e instanceof TypeError, e.message); }

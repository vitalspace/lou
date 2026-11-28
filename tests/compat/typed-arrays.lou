// TypedArray / ArrayBuffer / DataView: constructors, views, methods and endianness.

console.log(typeof Uint8Array, Uint8Array.name, Uint8Array.BYTES_PER_ELEMENT);
console.log(typeof ArrayBuffer, typeof SharedArrayBuffer, typeof DataView);
console.log(new Uint8Array([1, 2, 3]));

const a = new Uint8Array([1, 2, 3, 4]);
console.log(a.length, a.byteLength, a.byteOffset, a.BYTES_PER_ELEMENT);
console.log(a[0], a[3], a[4], a[-1]);
a[0] = 9;
a[9] = 7;
console.log(a.join(","));
console.log(a.at(0), a.at(-1), a.at(9));
console.log(a.indexOf(3), a.indexOf(8), a.includes(3), a.includes(8));

const sub = a.subarray(1, 3);
sub[0] = 20;
console.log(a.join(","), sub.join(","), sub.byteOffset, sub.length);
const copy = a.slice(1, 3);
copy[0] = 30;
console.log(a.join(","), copy.join(","), copy.byteOffset);

const b = new Uint8Array(5);
b.set([7, 8], 1);
console.log(b.join(","));
b.fill(4, 0, 2);
console.log(b.join(","));
const c = new Uint8Array([1, 2, 3, 4, 5]);
c.copyWithin(0, 2);
console.log(c.join(","));

const d = new Uint8Array([3, 1, 2]);
d.sort();
d.reverse();
console.log(d.join(","));
const e = new Int32Array([10, 2, 33]);
e.sort((x, y) => x - y);
console.log(e.join(","));

const f = new Uint8Array([1, 2, 3, 4]);
console.log(f.map(x => x * 2).join(","), f.filter(x => x % 2 === 0).join(","));
console.log(f.reduce((s, x) => s + x, 0), f.reduceRight((s, x) => s - x, 0));
console.log(f.find(x => x > 2), f.findIndex(x => x > 2));
console.log(f.some(x => x === 3), f.every(x => x > 0));
let total = 0;
f.forEach(x => total += x);
console.log(total);

console.log(Uint8Array.from([4, 5, 6]).join(","));
console.log(Uint8Array.from([1, 2], x => x * 3).join(","));
console.log(Int16Array.of(7, 8).join(","));

const i8 = new Int8Array([127, 128, 255, -129]);
console.log(i8.join(","));
const u8c = new Uint8ClampedArray([-1, 0.5, 1.5, 2.5, 254.6, 300]);
console.log(u8c.join(","));
const f32 = new Float32Array([1.1, 2.2]);
console.log(f32[0], f32[1]);
const f64 = new Float64Array([1.1, 2.2]);
console.log(f64[0], f64[1]);

const big = new BigInt64Array([1n, -2n, 9223372036854775807n]);
console.log(big.join(","));
const ubig = new BigUint64Array([1n, 18446744073709551615n]);
console.log(ubig.join(","));

const buf = new ArrayBuffer(8);
const bytes = new Uint8Array(buf);
bytes[0] = 0x12;
bytes[1] = 0x34;
bytes[2] = 0x56;
bytes[3] = 0x78;
const dv = new DataView(buf);
console.log(dv.byteOffset, dv.byteLength, dv.buffer === buf);
console.log(dv.getUint16(0).toString(16), dv.getUint16(0, true).toString(16));
console.log(dv.getUint32(0).toString(16), dv.getUint32(0, true).toString(16));
dv.setUint16(4, 0xabcd);
console.log(bytes[4].toString(16), bytes[5].toString(16));
dv.setUint16(6, 0xabcd, true);
console.log(bytes[6].toString(16), bytes[7].toString(16));
dv.setInt8(0, -1);
console.log(dv.getInt8(0), bytes[0]);
console.log(dv.getFloat64(0, true) === dv.getFloat64(0, true));

const part = new DataView(buf, 2, 4);
console.log(part.byteOffset, part.byteLength, part.getUint16(0).toString(16));
const copied = buf.slice(0, 4);
console.log(new Uint8Array(copied).join(","));

console.log(ArrayBuffer.isView(dv), ArrayBuffer.isView(buf), ArrayBuffer.isView(bytes));
console.log(bytes instanceof Uint8Array, bytes instanceof Int8Array);
console.log(buf instanceof ArrayBuffer, part instanceof DataView);

const shared = new SharedArrayBuffer(4);
const sharedView = new Uint16Array(shared);
sharedView[0] = 0x1234;
const sharedBytes = new Uint8Array(shared);
console.log(sharedBytes[0].toString(16), sharedBytes[1].toString(16), sharedView.buffer === shared);

const window = new Uint8Array(buf, 2, 2);
console.log(window.join(","), window.buffer === buf);
const cloned = new Uint8Array(f);
cloned[0] = 99;
console.log(cloned.join(","), f.join(","));

console.log(Object.keys(new Uint8Array([5, 6])).join(","));
console.log("0" in f, "4" in f, "length" in f, "map" in f);
console.log([...new Uint8Array([1, 2, 3])].join("|"));
console.log(Array.from(new Uint8Array([4, 5])).join("+"));

const iterated = [];
for (const value of new Uint8Array([7, 8])) iterated.push(value);
console.log(iterated.join("-"));
const entries = [];
for (const [index, value] of new Uint8Array([7, 8]).entries()) entries.push(index + ":" + value);
console.log(entries.join(","));
const keyIter = new Uint8Array([7, 8]).keys();
console.log(keyIter.next().value, keyIter.next().value, keyIter.next().done);
const valueIter = new Uint8Array([7, 8]).values();
console.log(valueIter.next().value, valueIter.next().value, valueIter.next().done);

console.log(String(new Uint8Array([1, 2, 3])));
console.log(new Uint8Array([1, 2, 3]).toString());

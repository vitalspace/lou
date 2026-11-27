// Object static methods: SameValue, entries, descriptors, integrity flags.
console.log(Object.is(NaN, NaN), Object.is(0, -0), Object.is(0, 0), Object.is("a", "a"));

const fromPairs = Object.fromEntries([["a", 1], ["b", 2]]);
console.log(JSON.stringify(fromPairs));

const m = new Map([["x", 10], ["y", 20]]);
console.log(JSON.stringify(Object.fromEntries(m)));

console.log(Object.getOwnPropertyNames({ b: 1, 0: 2 }).join(","));

const desc = Object.getOwnPropertyDescriptor({ a: 1 }, "a");
console.log(desc.value, desc.writable, desc.enumerable, desc.configurable);
console.log(Object.getOwnPropertyDescriptor({}, "x"));

const all = Object.getOwnPropertyDescriptors({ a: 1, b: 2 });
console.log(Object.getOwnPropertyNames(all).join(","));
console.log(all.a.value);

const defined = {};
Object.defineProperty(defined, "x", { value: 5 });
console.log(defined.x);

const frozen = { a: 1 };
console.log(Object.freeze(frozen) === frozen, Object.isFrozen(frozen), Object.isSealed(frozen), Object.isExtensible(frozen));
const sealed = { a: 1 };
Object.seal(sealed);
console.log(Object.isSealed(sealed), Object.isFrozen(sealed), Object.isExtensible(sealed));
const prevented = { a: 1 };
Object.preventExtensions(prevented);
console.log(Object.isExtensible(prevented), Object.isSealed(prevented), Object.isFrozen(prevented));
console.log(Object.isFrozen(1), Object.isExtensible(1), Object.isSealed(1));
console.log(Object.getOwnPropertySymbols({}).length);

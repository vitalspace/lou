// Proxy: get/set/has/deleteProperty/apply/construct and pass-through.

console.log(typeof Proxy, Proxy.name);

const reads = [];
const user = new Proxy({ name: "Alice", role: "admin" }, {
  get: function(target, prop) {
    reads.push("get:" + prop);
    if (prop in target) return target[prop];
    return "default";
  }
});
console.log(user.name, user.role, user.missing);
console.log(reads.join(","));

const writes = [];
const settings = new Proxy({ theme: "dark" }, {
  set: function(target, prop, value) {
    writes.push("set:" + prop + "=" + value);
    target[prop] = value;
    return true;
  }
});
settings.theme = "light";
settings.fontSize = 14;
console.log(settings.theme, settings.fontSize);
console.log(writes.join(","));

const checks = [];
const secure = new Proxy({ token: "abc" }, {
  has: function(target, prop) {
    checks.push("has:" + prop);
    return prop !== "secret" && prop in target;
  }
});
console.log("token" in secure, "secret" in secure, "missing" in secure);
console.log(checks.join(","));

const removals = [];
const cache = new Proxy({ a: 1, b: 2 }, {
  deleteProperty: function(target, prop) {
    removals.push("delete:" + prop);
    return delete target[prop];
  }
});
console.log(delete cache.a, "a" in cache, cache.b);
console.log(removals.join(","));

const plain = new Proxy({ x: 1, y: 2 }, {});
console.log(plain["x"]);
plain["x"] = 10;
plain.x += 5;
plain.x++;
console.log(plain.x, plain["x"], plain.y);
console.log(delete plain.y, "y" in plain);
console.log(delete plain.missing);
const sparse = new Proxy([1], {});
console.log(delete sparse[3], delete sparse.length, sparse.length);

const arrayProxy = new Proxy([1, 2], {});
console.log(arrayProxy[0], arrayProxy.length);
arrayProxy[2] = 3;
console.log(arrayProxy.length, arrayProxy[2]);

function sum(a, b) {
  return a + b;
}
const doubled = new Proxy(sum, {
  apply: function(target, thisArg, args) {
    return target(args[0], args[1]) * 2;
  }
});
console.log(doubled(2, 3), typeof doubled);
const direct = new Proxy(sum, {});
console.log(direct(4, 6));

function Person(name, age) {
  this.name = name;
  this.age = age;
}
const UpperPerson = new Proxy(Person, {
  construct: function(target, args) {
    return { name: args[0].toUpperCase(), age: args[1] };
  }
});
const p1 = new UpperPerson("alice", 30);
console.log(p1.name, p1.age);
const DefaultPerson = new Proxy(Person, {});
const p2 = new DefaultPerson("bob", 25);
console.log(p2.name, p2.age);

const methodHost = new Proxy({
  prefix: "hi",
  greet: function(name) { return this.prefix + " " + name; }
}, {});
console.log(methodHost.greet("carol"));

const inner = new Proxy({ value: 1 }, {});
const outer = new Proxy(inner, {
  get: function(target, prop) {
    if (prop === "value") return target[prop] + 1;
    return target[prop];
  }
});
console.log(outer.value);

const blocked = new Proxy({ x: 1 }, {
  set: function() { return false; },
  deleteProperty: function() { return false; }
});
blocked.x = 2;
console.log(blocked.x, delete blocked.x, blocked.x);

try {
  new Proxy(1, {});
} catch (err) {
  console.log(err.message);
}
try {
  Proxy({}, {});
} catch (err) {
  console.log(err.message);
}

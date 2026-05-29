console.log("=== 8. CHAINED SPREAD ===");

var filtered = [1, 2, 3, 4, 5].filter((x) => x > 2);
console.log([...filtered]);

var doubled = [1, 2, 3].map((x) => x * 10);
console.log([...doubled]);

var src = [5, 10, 15, 20];
var big = src.filter((x) => x > 10);
var dest = [];
dest.push(...big);
console.log(dest);

console.log([...a1, ...a2].push(100));

var user = { name: 'Alice', age: 30 };
var extended = { ...user, role: 'admin' };
console.log(extended.name);
console.log(extended.role);

var multi = [];    multi.push(...[1], ...[2], ...[3]);
console.log(multi);

console.log("=== 9. EDGE CASES ===");

console.log([...[]]);
console.log({ ...{} });
console.log([...[99]]);
console.log([...'']);

var outer = [1, [2, 3]];
var innerSpread = [...outer];
console.log(innerSpread);
console.log(innerSpread.length);

console.log({ ...{ a: 1 }, ...{ b: 2 }, ...{ c: 3 } });

console.log([...[1.5, 2.5]]);

console.log("=== 10. REAL-WORLD SCENARIOS ===");

var part1 = ['a', 'b'];
var part2 = ['c', 'd'];
var all = [...part1, ...part2];
console.log(all);

var clone = [...all];
console.log(clone);
console.log(clone.length);

var middle = [...part1, 'x', ...part2];
console.log(middle);

var config1 = { theme: 'dark', lang: 'en' };
var config2 = { lang: 'es', debug: true };
var config = { ...config1, ...config2 };
console.log(config);

var cloneObj = { ...config1 };
console.log(cloneObj);

var userInput = { name: 'Bob' };
var defaults = { role: 'user', active: true };
var userRecord = { ...defaults, ...userInput };
console.log(userRecord);

var uniqueVals = Set([1, 2, 2, 3, 3, 4]);
var uniqueArr = [...uniqueVals];
console.log(uniqueArr);

var entries = Map([['id', 1], ['name', 'Alice']]);
var mapEntries = [...entries];
console.log(mapEntries);

console.log(...['a', 'b', 'c']);

console.log("=== END ===");

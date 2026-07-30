// 1. Basic Map.groupBy
const items = [{type:'fruit'},{type:'veg'},{type:'fruit'}];
const g = Map.groupBy(items, i => i.type);
console.log('---Map basic---');
console.log(g.size);
console.log(g.get('fruit'));
console.log(g.get('veg'));

// 2. Excludes null keys (per ES2024)
const with_null = [1, 2, 3, 4];
const g2 = Map.groupBy(with_null, n => n % 2 === 0 ? 'even' : null);
console.log('---Excludes null---');
console.log(g2.size);
console.log(g2.get('even'));

// 3. Callback receives (item, index, array)
const arr = ['a', 'b', 'a', 'c', 'a'];
const g3 = Map.groupBy(arr, (item, idx) => idx % 2 === 0 ? 'even' : 'odd');
console.log('---Index arg---');
console.log(g3.get('even'));
console.log(g3.get('odd'));

// 4. Object.groupBy basic
const o = Object.groupBy(items, i => i.type);
console.log('---Object basic---');
console.log(Array.isArray(o.fruit));
console.log(Array.isArray(o.veg));
console.log(o.fruit.length);
console.log(o.veg.length);

// 5. Object.groupBy excludes null
const o2 = Object.groupBy([1,2,3,4], n => n % 2 === 0 ? 'even' : null);
console.log('---Object null excluded---');
console.log(Object.keys(o2).length);
console.log(o2.even);

// 6. Callback throw propagates
try {
    Map.groupBy([1,2,3], function () { throw new Error('boom'); });
    console.log('---Throw did not propagate---');
} catch (e) {
    console.log('---Throw propagated---');
    console.log(e.message);
}

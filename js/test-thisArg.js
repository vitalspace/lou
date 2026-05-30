console.log("filter:", [1,2,3].filter(function(x) { return x > this.min; }, {min: 2}));
console.log("map:", [1,2,3].map(function(x) { return x * this.factor; }, {factor: 2}));
console.log("every:", [1,2,3].every(function(x) { return x > this.min; }, {min: 0}));
console.log("some:", [1,2,3].some(function(x) { return x > this.max; }, {max: 2}));
console.log("find:", [1,2,3].find(function(x) { return x == this.target; }, {target: 2}));
console.log("findIndex:", [10,20,30].findIndex(function(x) { return x == this.target; }, {target: 20}));
console.log("findLast:", [1,2,3,2,1].findLast(function(x) { return x == this.val; }, {val: 2}));
console.log("findLastIndex:", [1,2,3,2,1].findLastIndex(function(x) { return x == this.val; }, {val: 2}));
console.log("flatMap:", [1,2].flatMap(function(x) { return [x, x * this.inc]; }, {inc: 10}));
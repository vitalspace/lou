// Rest parameters (...args) test suite - simplified for Lou compat
// Tests: function declarations, arrow functions, mixed params, spread + rest

// Basic rest in function declaration
function sum_all(first, ...rest) {
    var total = first;
    for (let i = 0; i < rest.length; i++) {
        total += rest[i];
    }
    return total;
}
console.log('sum_all(1, 2, 3):', sum_all(1, 2, 3));
console.log('sum_all(5):', sum_all(5));

// Rest-only function (no named params)
function collect(...items) {
    return items;
}
console.log('collect(1, 2, 3):', collect(1, 2, 3));
console.log('collect():', collect());
console.log('collect array:', Array.isArray(collect(1)));

// Rest-only arrow
const asArray = (...args) => args;
console.log('asArray(1, 2):', asArray(1, 2));
console.log('asArray():', asArray());

// Multiple named params with rest
function greet(greeting, ...names) {
    var result = greeting;
    for (let i = 0; i < names.length; i++) {
        result += ' ' + names[i];
    }
    return result;
}
console.log('greet1:', greet('Hello'));
console.log('greet2:', greet('Hi', 'Alice', 'Bob', 'Charlie'));

// Rest with mixed params
function checkArgs(a, b, ...rest) {
    return rest.length;
}
console.log('checkArgs(1):', checkArgs(1));
console.log('checkArgs(1, 2):', checkArgs(1, 2));
console.log('checkArgs(1, 2, 3, 4, 5):', checkArgs(1, 2, 3, 4, 5));

export const PI = 3.14;
export const E = 2.71;

export function add(a, b) {
    return a + b;
}

export function multiply(a, b) {
    return a * b;
}

export const greet = (name) => "hello " + name;

function internal_helper(x) {
    return x * 2;
}

export function process(x) {
    return internal_helper(x) + 1;
}

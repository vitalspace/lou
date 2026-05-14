// Block scoping with let
var outer = "global";
{
    let inner = "block";
    console.log(outer);
    console.log(inner);
}
// console.log(inner); would error — let is block-scoped

// Nested blocks
let x = 1;
{
    let x = 2;
    {
        let x = 3;
        console.log(x);
    }
    console.log(x);
}
console.log(x);

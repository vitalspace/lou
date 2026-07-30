// switch-case compat test
var x = 2;
switch (x) {
    case 1:
        console.log("one");
        break;
    case 2:
        console.log("two");
        break;
    default:
        console.log("other");
}

// Fall-through
switch (x) {
    case 1:
        console.log("A");
    case 2:
        console.log("B");
    case 3:
        console.log("C");
        break;
    default:
        console.log("D");
}

// Default anywhere
switch (x) {
    default:
        console.log("default-first");
        break;
    case 1:
        console.log("not-one");
        break;
    case 2:
        console.log("not-two");
        break;
}

// No match, no default
switch (x) {
    case 10:
        console.log("ten");
        break;
}
console.log("after-no-match");

// String discriminant
var s = "hello";
switch (s) {
    case "world":
        console.log("world");
        break;
    case "hello":
        console.log("hello-match");
        break;
}

// Boolean discriminant
switch (true) {
    case false:
        console.log("false");
        break;
    case true:
        console.log("true-match");
        break;
}

// Nested switch
switch (1) {
    case 1:
        switch (2) {
            case 1: console.log("a1"); break;
            case 2: console.log("a2"); break;
        }
        break;
    case 2:
        console.log("b");
        break;
}

// break vs no break
switch (3) {
    case 1:
        console.log("1");
        break;
    case 2:
        console.log("2");
        break;
    case 3:
        console.log("3-with-break");
        break;
    case 4:
        console.log("4");
        break;
}

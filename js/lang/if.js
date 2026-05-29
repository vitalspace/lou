// If/else if/else
var score = 85;
if (score >= 90) {
    console.log("A");
} else if (score >= 80) {
    console.log("B");
} else if (score >= 70) {
    console.log("C");
} else {
    console.log("F");
}

// Truthy/falsy
if (0) { console.log("zero truthy"); } else { console.log("zero falsy"); }
if (1) { console.log("one truthy"); }
if ("") { console.log("empty string truthy"); } else { console.log("empty string falsy"); }
if (null) { console.log("null truthy"); } else { console.log("null falsy"); }

// Without else
if (true) {
    console.log("no else");
}

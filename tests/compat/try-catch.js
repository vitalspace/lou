// try/catch exception handling
function test1() {
    console.log("--- basic try-catch ---");
    try {
        throw "error message";
    } catch (e) {
        console.log("caught:", e);
    }
    console.log("after catch");
}
test1();

function test2() {
    console.log("--- try-finally (no catch) ---");
    try {
        console.log("try body");
    } finally {
        console.log("finally runs");
    }
    console.log("after try-finally");
}
test2();

function test3() {
    console.log("--- try-catch-finally ---");
    try {
        throw "boom";
    } catch (e) {
        console.log("catch:", e);
    } finally {
        console.log("finally always runs");
    }
    console.log("after catch-finally");
}
test3();

function test4() {
    console.log("--- catch re-throw with finally ---");
    var result = "no thrown error caught";
    try {
        try {
            throw "inner";
        } catch (e) {
            console.log("inner catch:", e);
            throw "outer";
        } finally {
            console.log("inner finally");
        }
    } catch (e) {
        result = "caught outer: " + e;
    }
    console.log(result);
}
test4();

function test5() {
    console.log("--- nested try-catch ---");
    try {
        try {
            throw "nested";
        } catch (e) {
            console.log("caught nested:", e);
        }
        console.log("after nested");
    } catch (e) {
        console.log("should not reach:", e);
    }
    console.log("after outer try");
}
test5();

function test6() {
    console.log("--- finally with throw propagation ---");
    try {
        try {
            throw "original";
        } finally {
            console.log("finally runs, throw propagates");
        }
    } catch (e) {
        console.log("caught:", e);
    }
}
test6();

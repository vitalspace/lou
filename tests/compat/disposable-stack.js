// DisposableStack compat test - Node.js version

// Test 1: Basic defer in reverse order
{
    const results = [];
    const stack = new DisposableStack();
    stack.defer(() => results.push("first"));
    stack.defer(() => results.push("second"));
    stack.defer(() => results.push("third"));
    stack.dispose();
    console.log(results.join(","));
}

// Test 2: Dispose is idempotent
{
    const stack = new DisposableStack();
    let called = 0;
    stack.defer(() => { called++; });
    stack.dispose();
    stack.dispose();
    console.log(called === 1 ? "single-dispose-ok" : "multi-dispose-bug");
}

// Test 3: disposed getter
{
    const stack = new DisposableStack();
    console.log("before:" + stack.disposed);
    stack.dispose();
    console.log("after:" + stack.disposed);
}

// Test 4: Move resources to new stack
{
    const results = [];
    const stack1 = new DisposableStack();
    stack1.defer(() => results.push("from-move"));
    const stack2 = stack1.move();
    console.log("old-disposed:" + stack1.disposed);
    stack2.dispose();
    console.log(results.join(","));
}

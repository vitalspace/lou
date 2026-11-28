async function* count(start, end) {
  for (let i = start; i <= end; i++) {
    await Promise.resolve(i);
    yield i;
  }
  return "finished";
}

async function* doubled(values) {
  for await (const value of values) {
    yield value * 2;
  }
}
async function* chained() {
  yield Promise.resolve(9);
  yield* count(10, 11);
}
function* syncValues() {
  yield 3;
  yield 4;
}
async function* failing() {
  yield Promise.reject("boom");
}

async function main() {
  const gen = count(1, 3);
  const first = gen.next();
  console.log("promise", first instanceof Promise);

  let step = await first;
  console.log("step", step.value, step.done);
  step = await gen.next();
  console.log("step", step.value, step.done);
  step = await gen.next();
  console.log("step", step.value, step.done);
  step = await gen.next();
  console.log("step", step.value, step.done);

  for await (const value of count(4, 6)) {
    console.log("for", value);
  }

  for await (const value of doubled([1, 2])) {
    console.log("nested", value);
  }
  for await (const value of chained()) {
    console.log("chain", value);
  }

  const early = count(20, 22);
  console.log("early", (await early.next()).value);
  const closed = await early.return("stop");
  console.log("closed", closed.value, closed.done);

  for await (const value of [Promise.resolve(7), 8]) {
    console.log("array", value);
  }
  for await (const value of syncValues()) {
    console.log("sync", value);
  }

  for await (const char of "hi") {
    console.log("char", char);
  }

  try {
    await failing().next();
  } catch (error) {
    console.log("rejected", error);
  }

  try {
    await count(1, 1).throw("bang");
  } catch (error) {
    console.log("thrown", error);
  }

  const custom = {
    [Symbol.asyncIterator]() {
      let i = 0;
      return {
        async next() {
          i++;
          if (i > 2) return { value: undefined, done: true };
          return { value: i * 10, done: false };
        },
      };
    },
  };
  for await (const value of custom) {
    console.log("custom", value);
  }

  console.log("symbol", typeof Symbol.asyncIterator);
  console.log("symbolName", Symbol.asyncIterator);
}

main();
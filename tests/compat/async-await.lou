async function add(a, b) {
  return a + b;
}

async function fail() {
  throw new Error("boom");
}

class Counter {
  constructor(value) {
    this.value = value;
  }

  async double() {
    const value = await this.value;
    return value * 2;
  }
}

async function main() {
  console.log("start");

  const first = await add(2, 3);
  const second = await Promise.resolve(4);
  console.log("await", first, second);

  const fromExecutor = await new Promise((resolve) => resolve(10));
  console.log("executor", fromExecutor);

  const chained = await Promise.resolve(1)
    .then((value) => value + 1)
    .then((value) => value * 3);
  console.log("chain", chained);

  const finallyValue = await Promise.resolve("kept").finally(() => {
    console.log("cleanup");
  });
  console.log("finally", finallyValue);

  try {
    await fail();
  } catch (error) {
    console.log("caught", error.message);
  }

  const recovered = await Promise.reject("no")
    .catch((reason) => "recovered:" + reason);
  console.log(recovered);

  const all = await Promise.all([
    Promise.resolve(1),
    add(2, 3),
    "plain",
  ]);
  console.log("all", all.join(","));

  const settled = await Promise.allSettled([
    Promise.resolve("ok"),
    Promise.reject("bad"),
  ]);
  console.log("settled", settled[0].status, settled[0].value, settled[1].status, settled[1].reason);

  const raced = await Promise.race([add(1, 1), Promise.resolve(9)]);
  console.log("race", raced);

  const anyValue = await Promise.any([Promise.reject("nope"), add(3, 4)]);
  console.log("any", anyValue);

  const arrow = async (value) => {
    const doubled = await value * 2;
    return doubled;
  };
  console.log("arrow", await arrow(6));

  const counter = new Counter(7);
  console.log("method", await counter.double());

  const object = {
    base: 5,
    async plus(value) {
      return await this.base + value;
    },
  };
  console.log("object", await object.plus(6));

  console.log("done");
}

main();
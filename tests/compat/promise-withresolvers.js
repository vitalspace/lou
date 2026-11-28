async function main() {
  const first = Promise.withResolvers();
  console.log("types", typeof first.promise, typeof first.resolve, typeof first.reject);
  console.log("instance", first.promise instanceof Promise);

  first.resolve(42);
  first.reject("ignored");
  console.log("resolved", await first.promise);

  const failed = Promise.withResolvers();
  failed.reject(new Error("boom"));
  failed.resolve("ignored");
  try {
    await failed.promise;
  } catch (error) {
    console.log("rejected", error.message);
  }

  const a = Promise.withResolvers();
  const b = Promise.withResolvers();
  a.resolve("a");
  b.resolve("b");
  console.log("independent", await a.promise, await b.promise);

  const outer = Promise.withResolvers();
  const inner = Promise.withResolvers();
  outer.resolve(inner.promise);
  inner.resolve("adopted");
  console.log("adopted", await outer.promise);

  const empty = Promise.withResolvers();
  empty.resolve();
  console.log("empty", await empty.promise === undefined);

  const emptyReject = Promise.withResolvers();
  emptyReject.reject();
  try {
    await emptyReject.promise;
  } catch (error) {
    console.log("emptyReject", error === undefined);
  }

  const detached = Promise.withResolvers();
  const resolve = detached.resolve;
  resolve("detached");
  console.log("detached", await detached.promise);

  const { promise, resolve: resolveAlias, reject: rejectAlias } = Promise.withResolvers();
  console.log("aliases", typeof resolveAlias, typeof rejectAlias);
  resolveAlias("destructured");
  console.log("destructured", await promise);

  const keys = Promise.withResolvers();
  console.log("keys", Object.keys(keys).join(","));
}

main();
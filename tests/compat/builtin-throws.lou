// Errors thrown inside iteration callbacks must reach the outer catch.
try { [1, 2].forEach(function () { throw new Error("forEach"); }); } catch (e) { console.log("forEach:", e.message); }
try { [1].map(function () { throw new Error("map"); }); } catch (e) { console.log("map:", e.message); }
try { [1].filter(function () { throw new Error("filter"); }); } catch (e) { console.log("filter:", e.message); }
try { [1].reduce(function () { throw new Error("reduce"); }, 0); } catch (e) { console.log("reduce:", e.message); }
try { [1].some(function () { throw new Error("some"); }); } catch (e) { console.log("some:", e.message); }
try { [1].every(function () { throw new Error("every"); }); } catch (e) { console.log("every:", e.message); }
try { [1].find(function () { throw new Error("find"); }); } catch (e) { console.log("find:", e.message); }
const m = new Map([["a", 1]]);
try { m.forEach(function () { throw new Error("mapForEach"); }); } catch (e) { console.log("mapForEach:", e.message); }
const st = new Set([1]);
try { st.forEach(function () { throw new Error("setForEach"); }); } catch (e) { console.log("setForEach:", e.message); }
try { [3, 1, 2].sort(function () { throw new Error("sort"); }); } catch (e) { console.log("sort:", e.message); }

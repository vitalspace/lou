import defaultFunc from "./foo.js";
import { foo } from "./foo.js";

console.log(foo);              // "hello"
console.log(defaultFunc());    // "default"
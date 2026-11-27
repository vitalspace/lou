class Animal {
  constructor(name) {
    this.name = name;
  }
  speak() {
    return this.name + " makes a noise";
  }
}

class Dog extends Animal {
  constructor(name, breed) {
    super(name);
    this.breed = breed;
  }
  speak() {
    return super.speak() + ", " + this.name + " the " + this.breed + " barks";
  }
}

const dog = new Dog("Rex", "lab");
console.log(dog.speak());
console.log(dog instanceof Dog);
console.log(dog instanceof Animal);

class MathUtil {
  static square(x) {
    return x * x;
  }
  static get label() {
    return "MathUtil";
  }
}

console.log(MathUtil.square(5));
console.log(MathUtil.label);

class Counter {
  #count = 0;
  constructor(start = 0) {
    this.#count = start;
  }
  increment() {
    this.#count = this.#count + 1;
    return this;
  }
  get value() {
    return this.#count;
  }
  set value(next) {
    this.#count = next;
  }
}

const counter = new Counter(10);
counter.increment().increment();
console.log(counter.value);
counter.value = 3;
console.log(counter.value);

const Named = class {
  constructor(label) {
    this.label = label;
  }
  describe() {
    return "named:" + this.label;
  }
};

console.log(new Named("x").describe());

class Args {
  constructor(first, ...rest) {
    this.first = first;
    this.rest = rest.join(",");
  }
}

const args = new Args(1, 2, 3);
console.log(args.first, args.rest);

class Base {
  static get kind() {
    return "base";
  }
}
class Child extends Base {
  static get kind() {
    return "child:" + super.kind;
  }
}
console.log(Child.kind);

{
  class Local {
    hi() {
      return "local";
    }
  }
  console.log(new Local().hi());
}
console.log(typeof Local);

class Override {
  constructor() {
    return { custom: true };
  }
}
console.log(new Override().custom);

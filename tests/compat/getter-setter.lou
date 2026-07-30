// === Basic getter/setter ===
const obj = {
    _value: 0,
    get value() { return this._value; },
    set value(v) { this._value = v; }
};
obj.value = 42;
console.log(obj.value);

// === Getter only (read-only) ===
const config = {
    get version() { return "1.0.0"; }
};
console.log(config.version);

// === Fahrenheit/Celsius conversion ===
const temperature = {
    _celsius: 0,
    get fahrenheit() { return this._celsius * 9/5 + 32; },
    set fahrenheit(f) { this._celsius = (f - 32) * 5/9; }
};
temperature.fahrenheit = 212;
console.log(temperature._celsius);
console.log(temperature.fahrenheit);

// === Getter computing from properties ===
const circle = {
    radius: 5,
    get area() { return Math.PI * this.radius * this.radius; }
};
console.log(circle.area);

// === Setter with side effects ===
const user = {
    _name: "",
    get name() { return this._name; },
    set name(v) { this._name = v.toUpperCase(); }
};
user.name = "alice";
console.log(user.name);

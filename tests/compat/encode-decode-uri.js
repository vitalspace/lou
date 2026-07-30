// encodeURI
console.log(encodeURI("hello world"));
console.log(encodeURI("https://example.com/path?q=hello world"));
console.log(encodeURI("hello/world#fragment"));
console.log(encodeURI("café"));
console.log(encodeURI("日本語"));

// decodeURI
console.log(decodeURI("hello%20world"));
console.log(decodeURI("https://example.com/path?q=hello%20world"));
console.log(decodeURI("caf%C3%A9"));

// encodeURIComponent
console.log(encodeURIComponent("a&b=c d"));
console.log(encodeURIComponent("https://example.com"));
console.log(encodeURIComponent("hello/world"));
console.log(encodeURIComponent("日本語"));

// decodeURIComponent
console.log(decodeURIComponent("a%26b%3Dc%20d"));
console.log(decodeURIComponent("hello%20world"));
console.log(decodeURIComponent("caf%C3%A9"));

// Roundtrip
console.log(decodeURIComponent(encodeURIComponent("hello world & more")));
console.log(decodeURI(encodeURI("https://example.com/path?q=hello world")));

// Non-string coercion
console.log(encodeURI(undefined));
console.log(encodeURI(null));
console.log(encodeURI(true));
console.log(encodeURI(false));
console.log(decodeURI(undefined));
console.log(decodeURI(null));

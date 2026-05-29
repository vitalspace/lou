// String concatenation
console.log("hello" + " " + "world");
console.log("number: " + 42);
console.log(42 + " is the answer");
console.log("true is " + true);

// String comparison
console.log("abc" == "abc");
console.log("abc" != "xyz");

// String concat with variables
var hello = "hello";
var world = " world";
console.log(hello + world);

// Template strings
console.log(`hello from lou`);

// Strings with arrays
var words = ["hello", "world"];
console.log(words[0] + " " + words[1]);

// String.prototype.at()
console.log("hello".at(1));
console.log("hello".at(-1));
console.log("hello".at(10));
console.log("hello".at(-10));

// String.prototype.charAt()
console.log("hello".charAt(1));
console.log("hello".charAt());
console.log("hello".charAt(-1));
console.log("hello".charAt(10));

// String.prototype.charCodeAt()
console.log("abc".charCodeAt(1));
console.log("abc".charCodeAt());
console.log("abc".charCodeAt(-1));
console.log("abc".charCodeAt(10));

// String.prototype.codePointAt()
console.log("abc".codePointAt(1));
console.log("abc".codePointAt(0));
console.log("xyz".codePointAt(42));
console.log("abc".codePointAt(-1));

// String.prototype.concat()
console.log("Hello".concat(" ", "World"));
console.log("".concat("a", "b", "c"));
console.log("hello".concat());
console.log("number: ".concat(42));

// String.prototype.endsWith()
console.log("To be, or not to be, that is the question.".endsWith("question."));
console.log("To be, or not to be, that is the question.".endsWith("to be"));
console.log("To be, or not to be, that is the question.".endsWith("to be", 19));
console.log("hello".endsWith(""));
console.log("hello".endsWith("hello", 0));
console.log("hello world".endsWith("world", 5));
console.log("Hello".endsWith("hello"));

// String.prototype.includes()
console.log("The quick brown fox jumps over the lazy dog.".includes("fox"));
console.log("The quick brown fox jumps over the lazy dog.".includes("dog", 40));
console.log("The quick brown fox jumps over the lazy dog.".includes("dog", 41));
console.log("hello".includes(""));
console.log("Hello World".includes("world"));
console.log("hello".includes("x"));

// String.prototype.indexOf()
console.log("The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?".indexOf("dog"));
console.log("The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?".indexOf("dog", 41));
console.log("hello".indexOf("x"));
console.log("hello".indexOf("", 2));
console.log("hello world".indexOf("o", 5));
console.log("Hello".indexOf("hello"));

// String.prototype.isWellFormed()
console.log("hello".isWellFormed());
console.log("".isWellFormed());
console.log("abc\uD800".isWellFormed());
console.log("\uDC00abc".isWellFormed());
console.log("\uD83D\uDE00".isWellFormed());
console.log("a\uD800b".isWellFormed());

// String.prototype.lastIndexOf()
console.log("The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?".lastIndexOf("dog"));
console.log("hello".lastIndexOf("x"));
console.log("hello".lastIndexOf("", 2));
console.log("hello".lastIndexOf(""));
console.log("hello world".lastIndexOf("o", 4));
console.log("hello world".lastIndexOf("o", 6));
console.log("Hello".lastIndexOf("hello"));
console.log("banana".lastIndexOf("a"));

// String.prototype.localeCompare()
console.log("hello".localeCompare("hello"));
console.log("apple".localeCompare("banana"));
console.log("banana".localeCompare("apple"));
console.log("abc".localeCompare("abcd"));
console.log("abcd".localeCompare("abc"));

// String.prototype.match()
console.log("hello world".match("world"));
console.log("hello".match("xyz"));
console.log("hello".match(""));
console.log("hello42world".match(42));
console.log("hello hello".match("hello"));

// String.prototype.matchAll()
var matches = "test1test2".matchAll("test");
console.log(matches.next().value);
console.log(matches.next().value);
console.log(matches.next().done);
var nomatch = "hello".matchAll("xyz");
console.log(nomatch.next().done);
var intmatch = "a42b42c".matchAll(42);
console.log(intmatch.next().value);
console.log(intmatch.next().value);
console.log(intmatch.next().done);

// String.prototype.normalize()
var name1 = "\u0041\u006d\u00e9\u006c\u0069\u0065";
var name2 = "\u0041\u006d\u0065\u0301\u006c\u0069\u0065";
console.log(name1.normalize("NFC") === name2.normalize("NFC"));
console.log(name1.normalize("NFD") === name2.normalize("NFD"));
console.log(name1 === name2);

// String.prototype.padEnd()
console.log("Breaded Mushrooms".padEnd(25, "."));
console.log("Breaded Mushrooms".padEnd(25));
console.log("abc".padEnd(1));

// String.prototype.padStart()
console.log("5".padStart(2, "0"));
console.log("1234".padStart(10, "*"));
console.log("abc".padStart(1));

// String.prototype.repeat()
console.log("Because I'm happy. ".repeat(2));
console.log("abc".repeat(0));
console.log("x".repeat(3));

// String.prototype.replace()
var p = "The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?";
console.log(p.replace("dog", "monkey"));
console.log("aba".replace("a", "c"));
console.log("hello".replace("xyz", "foo"));

// String.prototype.replaceAll()
console.log("aba".replaceAll("a", "c"));
console.log("hello".replaceAll("l", ""));
console.log("hello".replaceAll("xyz", "foo"));
console.log(p.replaceAll("dog", "monkey"));

// String.prototype.search()
console.log("hello world".search("world"));
console.log("hello world".search("xyz"));
console.log("hello".search(""));
console.log("abc42def".search(42));

// String.prototype.slice()
console.log("The quick brown fox jumps over the lazy dog.".slice(31));
console.log("The quick brown fox jumps over the lazy dog.".slice(4, 19));
console.log("The quick brown fox jumps over the lazy dog.".slice(-4));
console.log("The quick brown fox jumps over the lazy dog.".slice(-9, -5));
console.log("hello".slice(10));
console.log("hello".slice(1, 3));

// String.prototype.split()
console.log("a,b,c".split(","));
console.log("hello".split(""));
console.log("a,b,c".split(",", 2));
console.log("hello".split());
console.log("a,b,".split(","));

// String.prototype.startsWith()
console.log("Saturday night plans".startsWith("Sat"));
console.log("Saturday night plans".startsWith("Sat", 3));
console.log("hello".startsWith(""));
console.log("hello".startsWith("x"));
console.log("Hello".startsWith("hello"));

// String.prototype.toUpperCase()
console.log("hello".toUpperCase());
console.log("Hello World".toUpperCase());
console.log("foo123!@#".toUpperCase());
console.log("".toUpperCase());

// String.prototype.toString()
console.log("hello".toString());
console.log("".toString());
var x = "hello world";
console.log(x.toString());

// String.prototype.toWellFormed()
console.log("hello".toWellFormed());
console.log("hello\uD800".toWellFormed());
console.log("\uDC00abc".toWellFormed());
console.log("a\uD800b".toWellFormed());
console.log("".toWellFormed());

// String.prototype.trim()
console.log("   Hello world!   ".trim());
console.log("Hello world!".trim());
console.log("   ".trim());
console.log("".trim());
console.log("\t\n  abc  \n\t".trim());

// String.prototype.trimStart()
console.log("   Hello world!   ".trimStart());
console.log("Hello world!   ".trimStart());
console.log("   ".trimStart());
console.log("".trimStart());

// String.prototype.trimEnd()
console.log("   Hello world!   ".trimEnd());
console.log("   Hello world!".trimEnd());
console.log("   ".trimEnd());
console.log("".trimEnd());

// String.prototype.valueOf()
console.log("hello".valueOf());
console.log("".valueOf());
var y = "hello world";
console.log(y.valueOf());

// String.prototype.toLowerCase()
console.log("HELLO".toLowerCase());
console.log("hello".toLowerCase());
console.log("Hello World".toLowerCase());
console.log("".toLowerCase());
console.log("FOO123!@#".toLowerCase());

// String.prototype.toLocaleLowerCase()
console.log("HELLO".toLocaleLowerCase());
console.log("istanbul".toLocaleLowerCase());
console.log("ISTANBUL".toLocaleLowerCase("en-US"));
console.log("".toLocaleLowerCase());

// String.prototype.toLocaleUpperCase()
console.log("hello".toLocaleUpperCase());
console.log("ISTANBUL".toLocaleUpperCase());
console.log("istanbul".toLocaleUpperCase("en-US"));
console.log("".toLocaleUpperCase());

// String.prototype.substr()
console.log("Mozilla".substr(1, 2));
console.log("Mozilla".substr(2));
console.log("Mozilla".substr(-3, 2));
console.log("Mozilla".substr(-10, 2));
console.log("Mozilla".substr(10));
console.log("Mozilla".substr(1, 0));
console.log("Mozilla".substr(1, -1));
console.log("Mozilla".substr(0));
console.log("Mozilla".substr(1, 100));
console.log("".substr(0));
console.log("hello".substr(1.9, 3.2));

// String.prototype.substring()
console.log("Mozilla".substring(1, 3));
console.log("Mozilla".substring(2));
console.log("Mozilla".substring(3, 1));
console.log("Mozilla".substring(-1, 3));
console.log("Mozilla".substring(0, 100));
console.log("Mozilla".substring(3, 3));
console.log("Mozilla".substring(-5, -2));
console.log("".substring(0));
console.log("hello".substring(1.9, 4.2));

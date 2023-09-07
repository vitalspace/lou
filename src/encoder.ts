const utf8: TextEncoder = new TextEncoder();
const encoder = (data : string) => utf8.encode(data + "\0");
export { encoder}
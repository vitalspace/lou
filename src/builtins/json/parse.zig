const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;
const evaluate = @import("../../evaluator.zig").evaluate;
const throwError = @import("../error.zig").throwError;

const Parser = struct {
    input: []const u8,
    pos: usize,
    env: *Types.Environment,
    line: usize = 1,
    col: usize = 1,
    last_error_msg: ?[]const u8 = null,

    fn peek(self: *const Parser) ?u8 {
        if (self.pos >= self.input.len) return null;
        return self.input[self.pos];
    }

    fn advance(self: *Parser) ?u8 {
        if (self.pos >= self.input.len) return null;
        const ch = self.input[self.pos];
        self.pos += 1;
        if (ch == '\n') {
            self.line += 1;
            self.col = 1;
        } else if (ch == '\r') {
            if (self.pos < self.input.len and self.input[self.pos] == '\n') {
                self.pos += 1;
            }
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        return ch;
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.input.len) {
            switch (self.input[self.pos]) {
                ' ', '\t' => {
                    self.pos += 1;
                    self.col += 1;
                },
                '\n' => {
                    self.pos += 1;
                    self.line += 1;
                    self.col = 1;
                },
                '\r' => {
                    self.pos += 1;
                    if (self.pos < self.input.len and self.input[self.pos] == '\n') {
                        self.pos += 1;
                    }
                    self.line += 1;
                    self.col = 1;
                },
                else => break,
            }
        }
    }

    /// Record the first error message encountered during parsing.
    fn reportError(self: *Parser, msg: []const u8) void {
        if (self.last_error_msg == null) {
            self.last_error_msg = msg;
        }
    }

    fn parseValue(self: *Parser) ?Types.Value {
        self.skipWhitespace();
        const ch = self.peek() orelse {
            self.reportError("unexpected end of data");
            return null;
        };
        return switch (ch) {
            '{' => self.parseObject(),
            '[' => self.parseArray(),
            '"' => self.parseString(),
            't' => self.parseLiteral("true", .{ .boolean = true }) orelse {
                self.reportError("unexpected token (expected 'true')");
                return null;
            },
            'f' => self.parseLiteral("false", .{ .boolean = false }) orelse {
                self.reportError("unexpected token (expected 'false')");
                return null;
            },
            'n' => self.parseLiteral("null", .{ .null = {} }) orelse {
                self.reportError("unexpected token (expected 'null')");
                return null;
            },
            '-', '0'...'9' => self.parseNumber(),
            else => {
                self.reportError("unexpected token");
                return null;
            },
        };
    }

    fn parseObject(self: *Parser) ?Types.Value {
        std.debug.assert(self.peek() == '{');
        _ = self.advance(); // consume '{'

        const obj = Types.ObjectValue.init(self.env.allocator) catch return null;
        self.env.objects.append(self.env.allocator, obj) catch {
            obj.deinit();
            return null;
        };

        self.skipWhitespace();
        if (self.peek() == '}') {
            _ = self.advance();
            return .{ .js_object = obj };
        }

        while (true) {
            self.skipWhitespace();
            if (self.peek() == null) {
                self.reportError("unexpected end of data (expected property name or '}')");
                return null;
            }
            if (self.peek() != '"') {
                self.reportError("expected property name (string)");
                return null;
            }
            const key = self.parseStringRaw() orelse {
                if (self.last_error_msg == null) {
                    self.reportError("expected property name (string)");
                }
                return null;
            };
            // Track the key string in owned_strings
            self.env.owned_strings.append(self.env.allocator, key) catch {};

            self.skipWhitespace();
            if (self.peek() != ':') {
                self.reportError("expected ':' after property name");
                return null;
            }
            _ = self.advance();

            const val = self.parseValue() orelse {
                if (self.last_error_msg == null) {
                    self.reportError("unexpected end of data (expected value)");
                }
                return null;
            };
            obj.properties.put(key, val) catch {};

            self.skipWhitespace();
            const next = self.peek() orelse {
                self.reportError("unexpected end of data (expected ',' or '}')");
                return null;
            };
            if (next == ',') {
                _ = self.advance();
                continue;
            } else if (next == '}') {
                _ = self.advance();
                return .{ .js_object = obj };
            } else {
                self.reportError("expected ',' or '}' after property value");
                return null;
            }
        }
    }

    fn parseArray(self: *Parser) ?Types.Value {
        std.debug.assert(self.peek() == '[');
        _ = self.advance(); // consume '['

        const arr = Types.ArrayObject.init(self.env.allocator) catch return null;
        self.env.arrays.append(self.env.allocator, arr) catch {
            arr.deinit();
            return null;
        };

        self.skipWhitespace();
        if (self.peek() == ']') {
            _ = self.advance();
            return .{ .array = arr };
        }

        while (true) {
            self.skipWhitespace();
            const val = self.parseValue() orelse {
                if (self.last_error_msg == null) {
                    self.reportError("unexpected end of data (expected value or ']')");
                }
                return null;
            };
            arr.elements.append(self.env.allocator, val) catch {};

            self.skipWhitespace();
            const next = self.peek() orelse {
                self.reportError("unexpected end of data (expected ',' or ']')");
                return null;
            };
            if (next == ',') {
                _ = self.advance();
                continue;
            } else if (next == ']') {
                _ = self.advance();
                return .{ .array = arr };
            } else {
                self.reportError("expected ',' or ']' after array element");
                return null;
            }
        }
    }

    fn parseString(self: *Parser) ?Types.Value {
        const raw = self.parseStringRaw() orelse return null;
        // Track in owned_strings
        self.env.owned_strings.append(self.env.allocator, raw) catch {};
        return .{ .string = raw };
    }

    fn parseStringRaw(self: *Parser) ?[]const u8 {
        if (self.peek() != '"') return null;
        _ = self.advance(); // consume opening quote

        var buf = std.ArrayList(u8).initCapacity(self.env.allocator, 32) catch return null;
        defer buf.deinit(self.env.allocator);

        while (self.peek()) |ch| {
            if (ch == '"') {
                _ = self.advance();
                const owned = buf.toOwnedSlice(self.env.allocator) catch return null;
                return owned;
            }
            if (ch == '\\') {
                _ = self.advance();
                const esc = self.peek() orelse {
                    self.reportError("bad escape");
                    return null;
                };
                _ = self.advance();
                switch (esc) {
                    '"' => buf.append(self.env.allocator, '"') catch return null,
                    '\\' => buf.append(self.env.allocator, '\\') catch return null,
                    '/' => buf.append(self.env.allocator, '/') catch return null,
                    'b' => buf.append(self.env.allocator, '\x08') catch return null,
                    'f' => buf.append(self.env.allocator, '\x0C') catch return null,
                    'n' => buf.append(self.env.allocator, '\n') catch return null,
                    'r' => buf.append(self.env.allocator, '\r') catch return null,
                    't' => buf.append(self.env.allocator, '\t') catch return null,
                    'u' => {
                        var hex: [4]u8 = undefined;
                        for (0..4) |i| {
                            const h = self.peek() orelse {
                                self.reportError("bad unicode escape");
                                return null;
                            };
                            _ = self.advance();
                            hex[i] = h;
                        }
                        const codepoint = std.fmt.parseInt(u21, &hex, 16) catch {
                            self.reportError("bad unicode escape");
                            return null;
                        };
                        var utf8_buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(codepoint, &utf8_buf) catch return null;
                        buf.appendSlice(self.env.allocator, utf8_buf[0..len]) catch return null;
                    },
                    else => {
                        // ES2025 24.5.1: any escape character not in the
                        // allowed set (`\"`, `\\`, `\/`, `\b`, `\f`, `\n`,
                        // `\r`, `\t`, `\uXXXX`) must throw SyntaxError.
                        // Match Node.js behavior — `JSON.parse('"\\x"')`
                        // raises `SyntaxError: Bad escape character ...`.
                        self.reportError("bad escape character in string literal");
                        return null;
                    },
                }
            } else if (ch < 0x20) {
                // Unescaped control characters are invalid in JSON strings
                self.reportError("bad control character in string literal");
                return null;
            } else {
                _ = self.advance();
                buf.append(self.env.allocator, ch) catch return null;
            }
        }
        self.reportError("unterminated string literal");
        return null;
    }

    fn parseLiteral(self: *Parser, expected: []const u8, value: Types.Value) ?Types.Value {
        if (self.pos + expected.len > self.input.len) return null;
        if (!std.mem.eql(u8, self.input[self.pos .. self.pos + expected.len], expected)) return null;
        // Update line/col for each character consumed
        for (expected) |ch| {
            if (ch == '\n') {
                self.line += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
            self.pos += 1;
        }
        return value;
    }

    fn parseNumber(self: *Parser) ?Types.Value {
        const start = self.pos;

        // Optional minus sign
        if (self.peek() == '-') _ = self.advance();

        // Integer part
        if (self.peek() == '0') {
            _ = self.advance();
        } else if (self.peek()) |ch| {
            if (ch >= '1' and ch <= '9') {
                _ = self.advance();
                while (self.peek()) |d| {
                    if (d >= '0' and d <= '9') {
                        _ = self.advance();
                    } else break;
                }
            } else {
                self.reportError("unexpected token (expected number)");
                return null;
            }
        } else {
            self.reportError("unexpected end of data (expected number)");
            return null;
        }

        // Decimal part
        var is_float = false;
        if (self.peek() == '.') {
            is_float = true;
            _ = self.advance();
            const frac_start = self.pos;
            while (self.peek()) |d| {
                if (d >= '0' and d <= '9') {
                    _ = self.advance();
                } else break;
            }
            if (self.pos == frac_start) {
                self.reportError("expected digit after decimal point");
                return null; // no digits after decimal point
            }
        }

        // Exponent part
        if (self.peek()) |e| {
            if (e == 'e' or e == 'E') {
                is_float = true;
                _ = self.advance();
                if (self.peek()) |sign| {
                    if (sign == '+' or sign == '-') _ = self.advance();
                }
                const exp_start = self.pos;
                while (self.peek()) |d| {
                    if (d >= '0' and d <= '9') {
                        _ = self.advance();
                    } else break;
                }
                if (self.pos == exp_start) {
                    self.reportError("expected digit after exponent");
                    return null; // no digits after exponent
                }
            }
        }

        const num_str = self.input[start..self.pos];

        if (is_float) {
            const f = std.fmt.parseFloat(f64, num_str) catch return null;
            return .{ .float = f };
        } else {
            // Try integer first
            if (std.fmt.parseInt(i64, num_str, 10)) |i| {
                return .{ .integer = i };
            } else |_| {
                // Might be out of i64 range, parse as float
                const f = std.fmt.parseFloat(f64, num_str) catch return null;
                return .{ .float = f };
            }
        }
    }
};

/// Try to get an AST function node from a Types.Value.
fn getFunctionNode(val: Types.Value, env: *Types.Environment) ?*Ast.Node {
    return switch (val) {
        .function => |f| @as(*Ast.Node, @ptrCast(@alignCast(f))),
        .string => |s| env.getFunction(s),
        else => null,
    };
}

/// Call the reviver function with (key, value) and return the result.
fn callReviverFn(reviver_fn: *Ast.Node, key: []const u8, value: Types.Value, env: *Types.Environment) !Types.Value {
    const func_params: []const []const u8 = switch (reviver_fn.*) {
        .FunctionDeclaration => |f| f.parameters,
        .ArrowFunction => |f| f.parameters,
        else => return value,
    };
    const func_body: *Ast.Node = switch (reviver_fn.*) {
        .FunctionDeclaration => |f| f.body,
        .ArrowFunction => |f| f.body,
        else => return value,
    };

    var func_env = Environment.initBlock(env.allocator, env) catch {
        return value;
    };
    defer func_env.deinit();

    if (func_params.len > 0) {
        // Heap-allocate the key string so it outlives this call (reviver may store it in arrays/objects).
        const key_copy = env.allocator.dupe(u8, key) catch return value;
        env.owned_strings.append(env.allocator, key_copy) catch {
            env.allocator.free(key_copy);
            return value;
        };
        func_env.setVar(func_params[0], .{ .string = key_copy }) catch {};
    }
    if (func_params.len > 1) {
        func_env.setVar(func_params[1], value) catch {};
    }

    const result = evaluate(func_body, &func_env) catch {
        return value;
    };
    return result;
}

/// Apply the reviver function to (key, value). If no reviver, returns the original value.
fn applyReviver(reviver_fn: ?*Ast.Node, key: []const u8, value: Types.Value, env: *Types.Environment) !Types.Value {
    if (reviver_fn) |fn_node| {
        return try callReviverFn(fn_node, key, value, env);
    }
    return value;
}

/// Walk the parsed value tree, applying reviver from leaves to root.
/// Returns true if the value should be deleted (reviver returned undefined).
fn walkReviver(val: *Types.Value, key: []const u8, reviver_fn: ?*Ast.Node, env: *Types.Environment) !bool {
    if (reviver_fn == null) return false;

    switch (val.*) {
        .js_object => |obj| {
            // Walk each property first (depth-first, leaves first)
            // Collect keys to avoid iterator invalidation when deleting.
            // We copy keys into owned strings because remove frees the hash-map key.
            var keys_to_check = std.ArrayList([]const u8).initCapacity(env.allocator, 0) catch return false;
            defer {
                for (keys_to_check.items) |k| {
                    env.allocator.free(k);
                }
                keys_to_check.deinit(env.allocator);
            }

            var it = obj.properties.iterator();
            while (it.next()) |entry| {
                const owned = env.allocator.dupe(u8, entry.key_ptr.*) catch continue;
                keys_to_check.append(env.allocator, owned) catch {
                    env.allocator.free(owned);
                    continue;
                };
            }

            for (keys_to_check.items) |k| {
                if (obj.properties.get(k)) |child_val| {
                    var mutable_child = child_val;
                    const should_delete = try walkReviver(&mutable_child, k, reviver_fn, env);
                    if (should_delete) {
                        _ = obj.properties.remove(k);
                    } else {
                        try obj.properties.put(k, mutable_child);
                    }
                }
            }
        },
        .array => |arr| {
            var i: usize = 0;
            while (i < arr.elements.items.len) {
                var idx_key_buf: [32]u8 = undefined;
                const idx_key = std.fmt.bufPrint(&idx_key_buf, "{d}", .{i}) catch "";
                const should_delete = try walkReviver(&arr.elements.items[i], idx_key, reviver_fn, env);
                if (should_delete) {
                    // For arrays, JSON.parse reviver replaces deleted elements with undefined
                    arr.elements.items[i] = .{ .void = {} };
                }
                i += 1;
            }
        },
        else => {},
    }

    // Apply reviver to this node
    const new_val = try applyReviver(reviver_fn, key, val.*, env);
    if (new_val == .void) {
        return true; // signal delete
    }
    val.* = new_val;
    return false;
}

pub fn Parse(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) {
        _ = throwError(env, "SyntaxError", .{ .string = "JSON.parse: unexpected end of data" });
        return .{ .value = .{ .void = {} } };
    }

    const input = switch (args[0]) {
        .string => |s| s,
        else => {
            _ = throwError(env, "SyntaxError", .{ .string = "JSON.parse: unexpected end of data" });
            return .{ .value = .{ .void = {} } };
        },
    };

    var parser = Parser{
        .input = input,
        .pos = 0,
        .env = env,
    };

    const result = parser.parseValue() orelse {
        const msg = parser.last_error_msg orelse "unexpected character";
        const err_fmt = std.fmt.allocPrint(env.allocator, "JSON.parse: {s} at line {d}, column {d}", .{ msg, parser.line, parser.col }) catch "JSON.parse: unexpected character";
        env.owned_strings.append(env.allocator, err_fmt) catch {};
        _ = throwError(env, "SyntaxError", .{ .string = err_fmt });
        return .{ .value = .{ .void = {} } };
    };

    parser.skipWhitespace();
    if (parser.pos != parser.input.len) {
        const msg = parser.last_error_msg orelse "unexpected character";
        const err_fmt = std.fmt.allocPrint(env.allocator, "JSON.parse: {s} at line {d}, column {d}", .{ msg, parser.line, parser.col }) catch "JSON.parse: unexpected character";
        env.owned_strings.append(env.allocator, err_fmt) catch {};
        _ = throwError(env, "SyntaxError", .{ .string = err_fmt });
        return .{ .value = .{ .void = {} } };
    }

    // Apply reviver if provided
    if (args.len >= 2) {
        const reviver_fn = getFunctionNode(args[1], env);
        if (reviver_fn == null) {
            _ = throwError(env, "TypeError", .{ .string = "JSON.parse: reviver must be a function" });
            return .{ .value = .{ .void = {} } };
        }

        // ECMAScript: create a holder object { "": result }, walk its "" property, then return it.
        // The holder itself is never passed to the reviver; only its properties are.
        const holder = Types.ObjectValue.init(env.allocator) catch return .{ .value = result };
        env.objects.append(env.allocator, holder) catch {};
        holder.properties.put("", result) catch {};

        // Walk the root property ("") of the holder, not the holder itself.
        if (holder.properties.get("")) |root_val| {
            var mutable_root = root_val;
            const should_delete = walkReviver(&mutable_root, "", reviver_fn, env) catch {
                return .{ .value = .{ .void = {} } };
            };
            if (should_delete) {
                _ = holder.properties.remove("");
            } else {
                holder.properties.put("", mutable_root) catch {};
            }
        }        if (holder.properties.get("")) |v| {
            return .{ .value = v };
        } else {
            return .{ .value = .{ .void = {} } };
        }
    }

    return .{ .value = result };
}

// =========================================================================
// Unit tests for Parse — locks down the parser shape so refactors don't
// silently regress (per specs/todos/pendientes/json-parse.md). Runs as part of
// `zig build test` (-g test).
// =========================================================================

const testing = std.testing;

fn parseInput(s: []const u8, env: *Types.Environment) Types.BuiltinResult {
    var args = [_]Types.Value{.{ .string = s }};
    return Parse(&args, env);
}

fn makeIdentNode(allocator: std.mem.Allocator, name: []const u8) !*Ast.Node {
    const node = try allocator.create(Ast.Node);
    node.* = .{ .Identifier = .{ .name = name } };
    return node;
}

fn makeVoidNode(allocator: std.mem.Allocator, operand: *Ast.Node) !*Ast.Node {
    const node = try allocator.create(Ast.Node);
    node.* = .{ .VoidExpression = .{ .operand = operand } };
    return node;
}

/// Build a synthetic FunctionDeclaration reviver with params ["key", "value"].
/// Caller is responsible for registering in env.synthetic_asts so the env's
/// deinit path runs freeAst on it (otherwise testing.allocator will leak).
fn makeReviver(allocator: std.mem.Allocator, body: *Ast.Node) !*Ast.Node {
    const params = try allocator.alloc([]const u8, 2);
    params[0] = "key";
    params[1] = "value";
    const node = try allocator.create(Ast.Node);
    node.* = .{ .FunctionDeclaration = .{
        .name = "reviver",
        .parameters = params,
        .body = body,
        .closure_env = null,
    }};
    return node;
}

fn trackAst(env: *Types.Environment, node: *Ast.Node) void {
    env.synthetic_asts.append(env.allocator, node) catch {};
}

fn expectSyntaxError(env: *Types.Environment) !void {
    try testing.expect(env.throw_hit);
    try testing.expect(env.throw_value == .js_object);
    const err = env.throw_value.js_object;
    try testing.expectEqualStrings("Error", err.properties.get("@@type").?.string);
    try testing.expectEqualStrings("SyntaxError", err.properties.get("@@subtype").?.string);
    try testing.expectEqualStrings("SyntaxError", err.properties.get("name").?.string);
    const message = err.properties.get("message").?.string;
    try testing.expect(std.mem.startsWith(u8, message, "JSON.parse:"));
}

/// Read a parsed numeric value (integer or float) as f64. Default JSON
/// literals — whole numbers that fit in i64, including `1` — are stored as
/// `.integer` per `parseNumber`'s `parseInt`-first branch. Tests that want
/// to assert a numeric value should use this helper instead of reading
/// `.float` directly, which would read garbage bits from `.integer` payloads.
/// The guarantees are:
///   - `.integer`  → cast to f64 via @floatFromInt (loses no precision for
///                    values that fit in i53, fine for compat tests)
///   - `.float`    → returned verbatim
/// Anything else (`.boolean`, `.string`, etc.) is a test bug — the helper
/// returns 0.0 with a tag check so the bug surfaces, not silently passes.
fn asF64(v: Types.Value) f64 {
    return switch (v) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => {
            std.debug.assert(false and "asF64: non-numeric JSON value");
            return 0.0;
        },
    };
}

test "Parse: simple string literal" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqualStrings("hello", parseInput("\"hello\"", &env).value.string);
}

test "Parse: string decode of standard JSON escape sequences" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqualStrings("\n", parseInput("\"\\n\"", &env).value.string);
    try testing.expectEqualStrings("\t", parseInput("\"\\t\"", &env).value.string);
    try testing.expectEqualStrings("\r", parseInput("\"\\r\"", &env).value.string);
    try testing.expectEqualStrings("\x08", parseInput("\"\\b\"", &env).value.string);
    try testing.expectEqualStrings("\x0C", parseInput("\"\\f\"", &env).value.string);
    try testing.expectEqualStrings("/", parseInput("\"\\/\"", &env).value.string);
    try testing.expectEqualStrings("\"", parseInput("\"\\\"\"", &env).value.string);
    try testing.expectEqualStrings("\\", parseInput("\"\\\\\"", &env).value.string);
}

test "Parse: \\uXXXX escape decodes as UTF-8 codepoint" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqualStrings("A", parseInput("\"\\u0041\"", &env).value.string);
    try testing.expectEqualStrings("é", parseInput("\"\\u00e9\"", &env).value.string);
    try testing.expectEqualStrings("☃", parseInput("\"\\u2603\"", &env).value.string); // 3-byte UTF-8
}

test "Parse: integer literal in i64 range stays integer (not float)" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expect(parseInput("42", &env).value == .integer);
    try testing.expectEqual(@as(i64, 42), parseInput("42", &env).value.integer);
}

test "Parse: 0 is integer (not float)" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expect(parseInput("0", &env).value == .integer);
    try testing.expectEqual(@as(i64, 0), parseInput("0", &env).value.integer);
}

test "Parse: negative integer stays integer" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqual(@as(i64, -42), parseInput("-42", &env).value.integer);
}

test "Parse: simple decimal becomes float" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqual(@as(f64, 42.5), parseInput("42.5", &env).value.float);
}

test "Parse: negative float" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqual(@as(f64, -1.5), parseInput("-1.5", &env).value.float);
}

test "Parse: exponent notation becomes float (even with integer magnitude)" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqual(@as(f64, 1e10), parseInput("1e10", &env).value.float);
    try testing.expectEqual(@as(f64, 0.000123), parseInput("1.23e-4", &env).value.float);
}

test "Parse: integer past 2^53 stays integer when it fits i64" {
    // MAX_SAFE_INTEGER+1 — 9_007_199_254_740_993 — fits in i64 (max ~9.22e18).
    // Zig's parseInt(10) reads it, so the parser stores it as .integer and
    // only falls back to .float on ACTUAL i64 overflow (test below).
    // This locks the boundary behaviour: above 2^53, integers stay integers
    // (NOT silently promoted to float).
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    const result = parseInput("9007199254740993", &env);
    try testing.expect(result.value == .integer);
    try testing.expectEqual(@as(i64, 9007199254740993), result.value.integer);
}

test "Parse: i64::MAX + 1 (overflow) parses as float without crashing" {
    // 9223372036854775808 — i64::MAX + 1, doesn't fit in i64.
    // Parser's parseInt fails, falls back to parseFloat → .float.
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    const result = parseInput("9223372036854775808", &env);
    try testing.expect(result.value == .float);
    try testing.expectEqual(@as(f64, 9223372036854775808.0), result.value.float);
}

test "Parse: parses true / false / null" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqual(true, parseInput("true", &env).value.boolean);
    try testing.expectEqual(false, parseInput("false", &env).value.boolean);
    try testing.expect(parseInput("null", &env).value == .null);
}

test "Parse: handles leading and trailing whitespace around value" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqual(@as(i64, 42), parseInput("  42  ", &env).value.integer);
    try testing.expectEqual(@as(f64, 1.5), parseInput("\n\t  1.5  \t\n", &env).value.float);
}

test "Parse: handles whitespace inside objects and arrays" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    const r = parseInput("  {  \"a\"  :  1  ,  \"b\"  :  [ 1 , 2 ] }  ", &env);
    try testing.expect(r.value == .js_object);
    try testing.expectEqual(@as(f64, 1.0), asF64(r.value.js_object.properties.get("a").?));
    const b = r.value.js_object.properties.get("b").?.array;
    try testing.expectEqual(@as(usize, 2), b.elements.items.len);
    try testing.expectEqual(@as(f64, 1.0), asF64(b.elements.items[0]));
    try testing.expectEqual(@as(f64, 2.0), asF64(b.elements.items[1]));
}

test "Parse: empty object and empty array" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqual(@as(usize, 0), parseInput("{}", &env).value.js_object.properties.iterator().len);
    try testing.expectEqual(@as(usize, 0), parseInput("[]", &env).value.array.elements.items.len);
}

test "Parse: mixed-type array preserves each tag" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    const arr = parseInput("[true, false, null, \"x\", 1, 1.5]", &env).value.array;
    try testing.expectEqual(@as(usize, 6), arr.elements.items.len);
    try testing.expect(arr.elements.items[0] == .boolean);
    try testing.expectEqual(true, arr.elements.items[0].boolean);
    try testing.expectEqual(false, arr.elements.items[1].boolean);
    try testing.expect(arr.elements.items[2] == .null);
    try testing.expectEqualStrings("x", arr.elements.items[3].string);
    try testing.expect(arr.elements.items[4] == .integer);
    try testing.expectEqual(@as(f64, 1.5), arr.elements.items[5].float);
}

test "Parse: object keys keep insertion order (needed for JSON.stringify roundtrip)" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    const obj = parseInput("{\"z\":1,\"a\":2,\"m\":3}", &env).value.js_object;

    var seen: [3][]const u8 = undefined;
    var i: usize = 0;
    var it = obj.properties.iterator();
    while (it.next()) |entry| : (i += 1) {
        seen[i] = entry.key_ptr.*;
    }
    try testing.expectEqualStrings("z", seen[0]);
    try testing.expectEqualStrings("a", seen[1]);
    try testing.expectEqualStrings("m", seen[2]);
}

test "Parse: SyntaxError on empty input" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = parseInput("", &env);
    try expectSyntaxError(&env);
}

test "Parse: SyntaxError on no args" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = Parse(&[_]Types.Value{}, &env);
    try expectSyntaxError(&env);
}

test "Parse: SyntaxError on non-string first arg" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{.{ .integer = 42 }};
    _ = Parse(&args, &env);
    try expectSyntaxError(&env);
}

test "Parse: SyntaxError on unknown escape character (\\x, \\v, \\0, \\a)" {
    // Locks the ES2025 24.5.1 fix: any escape outside the allowed set must throw.
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    // `inline for` (vs runtime `for`) keeps `esc` a comptime-known slice so the
    // `++` slice-concat below resolves at compile time. Without this Zig rejects
    // the expression: "unable to resolve comptime value".
    inline for ([_][]const u8{ "\\x", "\\v", "\\0", "\\a" }) |esc| {
        env.throw_hit = false;
        env.throw_value = .{ .void = {} };
        _ = parseInput("\"" ++ esc ++ "\"", &env);
        try testing.expect(env.throw_hit);
        try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
    }
}

test "Parse: SyntaxError on too-short unicode escape (\\u12)" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = parseInput("\"\\u12\"", &env);
    try testing.expect(env.throw_hit);
    try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
}

test "Parse: SyntaxError on non-hex unicode escape (\\uZZZZ)" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = parseInput("\"\\uZZZZ\"", &env);
    try testing.expect(env.throw_hit);
    try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
}

test "Parse: SyntaxError on unescaped control character in string" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    // \x01 is a literal control char (not JSON syntax).
    _ = parseInput("\"a\x01b\"", &env);
    try testing.expect(env.throw_hit);
    try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
}

test "Parse: SyntaxError on trailing garbage after toplevel value" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = parseInput("42 garbage", &env);
    try testing.expect(env.throw_hit);
    try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
}

test "Parse: no reviver returns parsed value verbatim" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    const result = parseInput("{\"a\":1,\"b\":\"x\"}", &env);
    try testing.expect(result.value == .js_object);
    try testing.expectEqual(@as(f64, 1.0), asF64(result.value.js_object.properties.get("a").?));
    try testing.expectEqualStrings("x", result.value.js_object.properties.get("b").?.string);
}

test "Parse: TypeError when reviver arg is not a function" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    var args = [_]Types.Value{
        .{ .string = "{\"a\":1}" },
        .{ .integer = 42 }, // not a function
    };
    _ = Parse(&args, &env);
    try testing.expect(env.throw_hit);
    try testing.expect(env.throw_value == .js_object);
    try testing.expectEqualStrings("TypeError", env.throw_value.js_object.properties.get("@@subtype").?.string);
    try testing.expectEqualStrings("TypeError", env.throw_value.js_object.properties.get("name").?.string);
}

test "Parse: pass-through reviver returns value parameter for every key" {
    // Body = `Identifier("value")`; the reviver framework binds the second
    // parameter to the value of the property under walk, so each leaf round-
    // trips. Locks invariant: a no-op reviver produces structurally-identical
    // output to no-reviver mode.
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const body = try makeIdentNode(allocator, "value");
    const reviver = try makeReviver(allocator, body);
    // Track only the root — freeAst recurses into body, so tracking the
    // children separately would triple-free the operand at env.deinit.
    trackAst(&env, reviver);

    var args = [_]Types.Value{
        .{ .string = "{\"a\":1,\"b\":\"x\"}" },
        // Types.Value.function is `*AstNode` (opaque, defined in runtime.zig);
        // our synthetic AST node is `*Ast.Node` (concrete union). Match the
        // existing pattern in `Parse`'s `.function => |f| @ptrCast(@alignCast(f))`
        // — only @ptrCast is needed since opaques have no alignment requirement.
        .{ .function = @ptrCast(reviver) },
    };
    const result = Parse(&args, &env);
    try testing.expect(result.value == .js_object);
    try testing.expectEqual(@as(f64, 1.0), asF64(result.value.js_object.properties.get("a").?));
    try testing.expectEqualStrings("x", result.value.js_object.properties.get("b").?.string);
}

test "Parse: voiding reviver (void anything) clears all object properties" {
    // Body = `VoidExpression{ operand = value }`. Void always returns .void
    // regardless of operand; per ECMAScript 24.5.1, a reviver that returns
    // undefined deletes the property. Walking bottom-up: leaves deleted first,
    // then the empty parent → reviver on parent returns void → holder's ""
    // key removed → final result is undefined (.void).
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const operand = try makeIdentNode(allocator, "value");
    const body = try makeVoidNode(allocator, operand);
    const reviver = try makeReviver(allocator, body);
    // Track only the root reviver — freeAst recurses into body, then operand.
    trackAst(&env, reviver);

    var args = [_]Types.Value{
        .{ .string = "{\"a\":1,\"b\":2}" },
        .{ .function = @ptrCast(reviver) },
    };
    const result = Parse(&args, &env);
    try testing.expect(result.value == .void);
}

test "Parse: voiding reviver replaces all array elements with undefined" {
    // For arrays, deletion from deep walk replaces elements with .void; then
    // the array's own reviver returns void → holder loses "" → final .void.
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const operand = try makeIdentNode(allocator, "value");
    const body = try makeVoidNode(allocator, operand);
    const reviver = try makeReviver(allocator, body);
    trackAst(&env, reviver);

    var args = [_]Types.Value{
        .{ .string = "[1,2,3]" },
        .{ .function = @ptrCast(reviver) },
    };
    const result = Parse(&args, &env);
    try testing.expect(result.value == .void);
}

test "Parse: leading zero with extra digits throws SyntaxError" {
    // ES2025 strictly forbids leading zeros except for "0" itself.
    // Our parser enforces this NOT via parseInt (which just reads the first
    // "0" and stops) but via Parse's trailing-garbage check after parseNumber
    // returns. Lock this strict behavior so a future refactor that, say,
    // skips the trailing-input check or moves to a greedier parseInt branch,
    // would explicitly fail.
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    inline for ([_][]const u8{ "042", "-042", "01", "013", "00" }) |input| {
        env.throw_hit = false;
        env.throw_value = .{ .void = {} };
        _ = parseInput(input, &env);
        try testing.expect(env.throw_hit);
        try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
    }
}

test "Parse: bare 0 parses cleanly as integer (no trailing error)" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try testing.expectEqual(@as(i64, 0), parseInput("0", &env).value.integer);
}

test "Parse: SyntaxError on trailing comma in array" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = parseInput("[1,]", &env);
    try testing.expect(env.throw_hit);
    try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
}

test "Parse: SyntaxError on trailing comma in object" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = parseInput("{\"a\":1,}", &env);
    try testing.expect(env.throw_hit);
    try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
}

test "Parse: SyntaxError on lone opening brace" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = parseInput("{", &env);
    try testing.expect(env.throw_hit);
    try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
}

test "Parse: SyntaxError on lone opening bracket" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = parseInput("[", &env);
    try testing.expect(env.throw_hit);
    try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
}

test "Parse: SyntaxError on lone closing brace" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = parseInput("}", &env);
    try testing.expect(env.throw_hit);
    try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
}

test "Parse: duplicate object keys: last write wins" {
    // Locks the collision semantics of `obj.properties.put` (a string-keyed
    // hash-map, so re-inserting the same key replaces the value).
    // Whole-number JSON literals are stored as `.integer` per parseNumber's
    // parseInt-first branch — assert the tag explicitly, NOT `.float` (which
    // would read garbage bits from the `.integer` payload).
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    const obj = parseInput("{\"a\":1,\"a\":2}", &env).value.js_object;
    var count: usize = 0;
    var saw_int_2 = false;
    var it = obj.properties.iterator();
    while (it.next()) |entry| {
        count += 1;
        if (std.mem.eql(u8, entry.key_ptr.*, "a")) {
            try testing.expect(entry.value_ptr.* == .integer);
            try testing.expectEqual(@as(i64, 2), entry.value_ptr.integer);
            saw_int_2 = true;
        }
    }
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expect(saw_int_2);
}

test "Parse: deeply nested object/array parses without crashing" {
    // Sanity lock — exercises the recursion pathway. Depth 8 keeps runtime
    // bounded while still flagging any unbounded recursion regressions.
    // Asserts the LEAF VALUE (not just the .js_object tag) so a future refactor
    // that mis-walks recursion can't pass with a `null` left at the leaf.
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    const input = "{\"a\":{\"b\":{\"c\":{\"d\":{\"e\":{\"f\":{\"g\":{\"h\":1}}}}}}}}";
    // Walk down the chain manually to verify the recursive parse preserves values.
    var outer = parseInput(input, &env).value.js_object;
    const path = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h" };
    for (path[0 .. path.len - 1]) |k| {
        const next_val = outer.properties.get(k).?;
        try testing.expect(next_val == .js_object);
        outer = next_val.js_object;
    }
    try testing.expectEqual(@as(i64, 1), outer.properties.get(path[path.len - 1]).?.integer);
}

test "Parse: lone \\u with no hex digits after throws SyntaxError" {
    // Locks that `\\u` followed by no chars hits the existing 'bad unicode
    // escape' branch (NOT a silent unsupported escape that exists in some
    // legacy implementations).
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    _ = parseInput("\"\\u\"", &env);
    try testing.expect(env.throw_hit);
    try testing.expectEqualStrings("SyntaxError", env.throw_value.js_object.properties.get("name").?.string);
}


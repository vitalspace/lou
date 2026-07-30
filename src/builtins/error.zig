const std = @import("std");
const Types = @import("../types/types.zig");

/// List of all 7 Error class names used by the hierarchy check
/// for `e instanceof Error` (which must match ALL error subclasses).
pub const ERROR_SUBTYPES = [_][]const u8{
    "Error",
    "TypeError",
    "RangeError",
    "ReferenceError",
    "SyntaxError",
    "EvalError",
    "URIError",
};

/// Build an Error class instance as a `.js_object` with:
///   `@@type      = "Error"`     (string literal — used by MethodCall to
///                                dispatch `.toString()`)
///   `@@subtype   = <subtype>`   (used by `instanceof` to discriminate subclasses)
///   `name        = <subtype>`   (display name, e.g. `e.name === "TypeError"`)
///   `message     = <message>`   (first arg coerced to string, or "" if absent)
///
/// Memory ownership:
///   - The new `ObjectValue` is appended to `env.objects` (freed on env deinit).
///   - All owned strings (typed duplicates) are appended to `env.owned_strings`
///     so they outlive the constructor call and are released on env deinit.
///   - `@@type` uses a static-literal `"Error"` — same shape as `Date.@@type`
///     in `date/constructor.zig`, no allocation / no leak risk.
///
/// On any alloc failure we explicitly `alloc.free()` the just-allocated
/// dangling string AND pop/deinit the partial object, so the env stays
/// consistent. (Pattern matches `date/constructor.zig`.)
/// Build an Error class instance via `makeErrorObject` AND throw it via the
/// environment's throw state (`throw_value` + `throw_hit`). Returns `.void`
/// so the caller can `return throwError(env, "RangeError", msg)` directly.
///
/// Use from any path that needs to surface a JS exception (e.g. an infix
/// operator that detects a runtime error). The caller must NOT also `return
/// try` the value as if it were a normal evaluation — the throw state is
/// what unrolls through `try { } catch(e)`, the returned `.void` is what
/// reaches the catch-block binding.
///
/// Memory: the new `ObjectValue` is appended to `env.objects` by
/// `makeErrorObject`; storing the same pointer in `env.throw_value` is just
/// an additional reference. No double-free risk because the lifecycle is
/// exclusively owned by `env.objects` + the env's `deinit`.
pub fn throwError(env: *Types.Environment, subtype: []const u8, message_arg: ?Types.Value) Types.Value {
    const result = makeErrorObject(env, subtype, message_arg);
    switch (result) {
        .value => |val| {
            if (val == .js_object) {
                env.throw_value = val;
                env.throw_hit = true;
            }
        },
        .void => {},
    }
    return .{ .void = {} };
}

fn makeErrorObject(env: *Types.Environment, subtype: []const u8, message_arg: ?Types.Value) Types.BuiltinResult {
    const alloc = env.allocator;
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };

    const obj = Types.ObjectValue.init(alloc) catch return fail;
    env.objects.append(alloc, obj) catch {
        obj.deinit();
        return fail;
    };

    const name_owned = alloc.dupe(u8, subtype) catch {
        _ = env.objects.pop();
        obj.deinit();
        return fail;
    };
    env.owned_strings.append(alloc, name_owned) catch {
        alloc.free(name_owned);
        _ = env.objects.pop();
        obj.deinit();
        return fail;
    };

    // Static-literal `@@type` — matches Date pattern, no allocation needed.
    obj.properties.put("@@type", .{ .string = "Error" }) catch {};
    obj.properties.put("@@subtype", .{ .string = name_owned }) catch {};
    obj.properties.put("name", .{ .string = name_owned }) catch {};

    // `message`: coerce first arg to string, fallback to "" on failure.
    const message_owned: []const u8 = blk: {
        const arg = message_arg orelse break :blk "";
        break :blk switch (arg) {
            .string => |s| blk2: {
                if (s.len == 0) break :blk2 "";
                const dup = alloc.dupe(u8, s) catch break :blk2 "";
                env.owned_strings.append(alloc, dup) catch {
                    alloc.free(dup);
                    break :blk2 "";
                };
                break :blk2 dup;
            },
            .integer => |i| blk2: {
                var buf: [32]u8 = undefined;
                const w = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break :blk2 "";
                const dup = alloc.dupe(u8, buf[0..w.len]) catch break :blk2 "";
                env.owned_strings.append(alloc, dup) catch {
                    alloc.free(dup);
                    break :blk2 "";
                };
                break :blk2 dup;
            },
            .float => |f| blk2: {
                if (std.math.isNan(f)) {
                    const dup = alloc.dupe(u8, "NaN") catch break :blk2 "";
                    env.owned_strings.append(alloc, dup) catch {
                        alloc.free(dup);
                        break :blk2 "";
                    };
                    break :blk2 dup;
                }
                var buf: [64]u8 = undefined;
                const w = std.fmt.bufPrint(&buf, "{d}", .{f}) catch break :blk2 "";
                const dup = alloc.dupe(u8, buf[0..w.len]) catch break :blk2 "";
                env.owned_strings.append(alloc, dup) catch {
                    alloc.free(dup);
                    break :blk2 "";
                };
                break :blk2 dup;
            },
            .boolean => |b| blk2: {
                const dup = alloc.dupe(u8, if (b) "true" else "false") catch break :blk2 "";
                env.owned_strings.append(alloc, dup) catch {
                    alloc.free(dup);
                    break :blk2 "";
                };
                break :blk2 dup;
            },
            .void => blk2: {
                const dup = alloc.dupe(u8, "undefined") catch break :blk2 "";
                env.owned_strings.append(alloc, dup) catch {
                    alloc.free(dup);
                    break :blk2 "";
                };
                break :blk2 dup;
            },
            .null => blk2: {
                const dup = alloc.dupe(u8, "null") catch break :blk2 "";
                env.owned_strings.append(alloc, dup) catch {
                    alloc.free(dup);
                    break :blk2 "";
                };
                break :blk2 dup;
            },
            .big_int => |bi| blk2: {
                const digits = bi.toString(alloc) catch break :blk2 "";
                env.owned_strings.append(alloc, digits) catch {
                    alloc.free(digits);
                    break :blk2 "";
                };
                break :blk2 digits;
            },
            else => "",
        };
    };
    obj.properties.put("message", .{ .string = message_owned }) catch {};

    return .{ .value = .{ .js_object = obj } };
}

pub fn ErrorConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return makeErrorObject(env, "Error", if (args.len > 0) args[0] else null);
}

pub fn TypeErrorConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return makeErrorObject(env, "TypeError", if (args.len > 0) args[0] else null);
}

pub fn RangeErrorConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return makeErrorObject(env, "RangeError", if (args.len > 0) args[0] else null);
}

pub fn ReferenceErrorConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return makeErrorObject(env, "ReferenceError", if (args.len > 0) args[0] else null);
}

pub fn SyntaxErrorConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return makeErrorObject(env, "SyntaxError", if (args.len > 0) args[0] else null);
}

pub fn EvalErrorConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return makeErrorObject(env, "EvalError", if (args.len > 0) args[0] else null);
}

pub fn URIErrorConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return makeErrorObject(env, "URIError", if (args.len > 0) args[0] else null);
}

/// `Error.prototype.toString()` — returns `"<name>: <message>"` or just
/// `"<name>"` if message is empty (per ES2025).
pub fn ErrorToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    if (args[0] != .js_object) return .{ .value = .{ .void = {} } };
    const obj = args[0].js_object;

    const name: []const u8 = blk: {
        if (obj.properties.get("name")) |n| {
            if (n == .string and n.string.len > 0) break :blk n.string;
        }
        break :blk "Error";
    };
    const message: []const u8 = blk: {
        if (obj.properties.get("message")) |m| {
            if (m == .string) break :blk m.string;
        }
        break :blk "";
    };

    // Use shared allocator idioms instead of ArrayList to dodge managed-
    // vs-unmanaged API confusion that was silently swallowing into void.
    const owned: []const u8 = if (message.len > 0)
        std.fmt.allocPrint(env.allocator, "{s}: {s}", .{ name, message }) catch {
            return .{ .value = .{ .void = {} } };
        }
    else
        env.allocator.dupe(u8, name) catch {
            return .{ .value = .{ .void = {} } };
        };
    env.owned_strings.append(env.allocator, owned) catch {
        env.allocator.free(owned);
        return .{ .value = .{ .void = {} } };
    };
    return .{ .value = .{ .string = owned } };
}

pub const ERROR_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "toString", .func = ErrorToString },
};

pub const ERROR_OBJECT = Types.BuiltinObjectImpl{
    .name = "Error",
    .methods = &ERROR_METHODS,
};

/// BuiltinObject entries for each Error subtype so `instanceof` works
/// (e.g. `e instanceof SyntaxError`). Each needs a `.name` matching the
/// constructor name so the `instanceof` handler can compare.
pub const SYNTAX_ERROR_OBJECT = Types.BuiltinObjectImpl{
    .name = "SyntaxError",
    .methods = &.{},
};
pub const TYPE_ERROR_OBJECT = Types.BuiltinObjectImpl{
    .name = "TypeError",
    .methods = &.{},
};
pub const RANGE_ERROR_OBJECT = Types.BuiltinObjectImpl{
    .name = "RangeError",
    .methods = &.{},
};
pub const REFERENCE_ERROR_OBJECT = Types.BuiltinObjectImpl{
    .name = "ReferenceError",
    .methods = &.{},
};
pub const EVAL_ERROR_OBJECT = Types.BuiltinObjectImpl{
    .name = "EvalError",
    .methods = &.{},
};
pub const URI_ERROR_OBJECT = Types.BuiltinObjectImpl{
    .name = "URIError",
    .methods = &.{},
};

const testing = std.testing;

// Helper: assert that an object's property `key` is the given string.
fn expectPropString(obj: *const Types.ObjectValue, key: []const u8, expected: []const u8) !void {
    const v = obj.properties.get(key) orelse {
        std.debug.print("missing key: {s}\n", .{key});
        return error.TestExpectedProperty;
    };
    if (v != .string) return error.TestExpectedStringProperty;
    try testing.expectEqualStrings(expected, v.string);
}

test "Error() with no args creates Error name and empty message" {
    var env = try @import("../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const result = ErrorConstructor(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .js_object);
    const obj = result.value.js_object;

    try expectPropString(obj, "name", "Error");
    // `@@type` is a static-literal "Error" (allocated nowhere) — distinct
    // from the heap-allocated `name`. The shared-buffer invariant below
    // is specifically about `name` ↔ `@@subtype`, both written with the
    // same `name_owned` dupe inside makeErrorObject.
    try expectPropString(obj, "@@type", "Error");
    try expectPropString(obj, "@@subtype", "Error");
    try expectPropString(obj, "message", "");

    // name ↔ @@subtype must share the same backing buffer (same ptr
    // AND same len) so makeErrorObject can store one `name_owned` dupe
    // under both keys without leaking on deinit.
    const name_val = obj.properties.get("name").?.string;
    const subtype_val = obj.properties.get("@@subtype").?.string;
    try testing.expectEqual(@intFromPtr(name_val.ptr), @intFromPtr(subtype_val.ptr));
    try testing.expectEqual(name_val.len, subtype_val.len);
}

test "Error(string) sets message verbatim" {
    var env = try @import("../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const msg = try testing.allocator.dupe(u8, "boom!");
    env.owned_strings.append(testing.allocator, msg) catch {};

    var args = [_]Types.Value{.{ .string = msg }};
    const result = ErrorConstructor(&args, &env);
    try testing.expect(result.value == .js_object);
    try expectPropString(result.value.js_object, "name", "Error");
    try expectPropString(result.value.js_object, "message", "boom!");
}

test "TypeError/RangeError/ReferenceError/SyntaxError/EvalError/URIError set correct name and @@subtype" {
    var env = try @import("../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const msg = try testing.allocator.dupe(u8, "x");
    env.owned_strings.append(testing.allocator, msg) catch {};
    var args = [_]Types.Value{.{ .string = msg }};

    const type_obj = TypeErrorConstructor(&args, &env).value.js_object;
    try expectPropString(type_obj, "name", "TypeError");
    try expectPropString(type_obj, "@@subtype", "TypeError");

    const range_obj = RangeErrorConstructor(&args, &env).value.js_object;
    try expectPropString(range_obj, "name", "RangeError");
    try expectPropString(range_obj, "@@subtype", "RangeError");

    const ref_obj = ReferenceErrorConstructor(&args, &env).value.js_object;
    try expectPropString(ref_obj, "name", "ReferenceError");
    try expectPropString(ref_obj, "@@subtype", "ReferenceError");

    const syntax_obj = SyntaxErrorConstructor(&args, &env).value.js_object;
    try expectPropString(syntax_obj, "name", "SyntaxError");
    try expectPropString(syntax_obj, "@@subtype", "SyntaxError");

    const eval_obj = EvalErrorConstructor(&args, &env).value.js_object;
    try expectPropString(eval_obj, "name", "EvalError");
    try expectPropString(eval_obj, "@@subtype", "EvalError");

    const uri_obj = URIErrorConstructor(&args, &env).value.js_object;
    try expectPropString(uri_obj, "name", "URIError");
    try expectPropString(uri_obj, "@@subtype", "URIError");

    // All 7 subclasses share `@@type = "Error"` (this is the marker the
    // evaluator's `instanceof Error` branch matches — see evaluator.zig).
    const all = [_]*const Types.ObjectValue{
        type_obj, range_obj, ref_obj, syntax_obj, eval_obj, uri_obj,
    };
    for (all) |o| try expectPropString(o, "@@type", "Error");
}

test "Error coerces non-string messages via ToString-like coercion" {
    var env = try @import("../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    // integer
    var i_args = [_]Types.Value{.{ .integer = 42 }};
    try expectPropString(ErrorConstructor(&i_args, &env).value.js_object, "message", "42");

    // float — `1.5` is short enough that `{d}` formats it as `"1.5"`
    var f_args = [_]Types.Value{.{ .float = 1.5 }};
    try expectPropString(ErrorConstructor(&f_args, &env).value.js_object, "message", "1.5");

    // float NaN -> "NaN"
    var nan_args = [_]Types.Value{.{ .float = std.math.nan(f64) }};
    try expectPropString(ErrorConstructor(&nan_args, &env).value.js_object, "message", "NaN");

    // boolean
    var t_args = [_]Types.Value{.{ .boolean = true }};
    try expectPropString(ErrorConstructor(&t_args, &env).value.js_object, "message", "true");
    var f2_args = [_]Types.Value{.{ .boolean = false }};
    try expectPropString(ErrorConstructor(&f2_args, &env).value.js_object, "message", "false");

    // void -> "undefined"
    var v_args = [_]Types.Value{.{ .void = {} }};
    try expectPropString(ErrorConstructor(&v_args, &env).value.js_object, "message", "undefined");

    // null -> "null"
    var n_args = [_]Types.Value{.{ .null = {} }};
    try expectPropString(ErrorConstructor(&n_args, &env).value.js_object, "message", "null");
}

test "Error coerces BigInt message to decimal digits" {
    var env = try @import("../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const bi = try @import("../ast.zig").BigIntValue.fromString(testing.allocator, "12345");
    env.bigints.append(testing.allocator, bi) catch {};

    var args = [_]Types.Value{.{ .big_int = bi }};
    try expectPropString(ErrorConstructor(&args, &env).value.js_object, "message", "12345");
}

test "ErrorToString formats \"Name: message\"" {
    var env = try @import("../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const msg = try testing.allocator.dupe(u8, "boom!");
    env.owned_strings.append(testing.allocator, msg) catch {};
    var ctor_args = [_]Types.Value{.{ .string = msg }};

    const obj = ErrorConstructor(&ctor_args, &env).value.js_object;
    var args = [_]Types.Value{.{ .js_object = obj }};
    const result = ErrorToString(&args, &env);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("Error: boom!", result.value.string);
}

test "ErrorToString with empty message returns just the name" {
    var env = try @import("../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const obj = ErrorConstructor(&[_]Types.Value{}, &env).value.js_object;
    var args = [_]Types.Value{.{ .js_object = obj }};
    const result = ErrorToString(&args, &env);
    try testing.expect(result.value == .string);
    try testing.expectEqualStrings("Error", result.value.string);
}

test "TypeError.prototype.toString uses TypeError name" {
    var env = try @import("../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const msg = try testing.allocator.dupe(u8, "bad type");
    env.owned_strings.append(testing.allocator, msg) catch {};
    var ctor_args = [_]Types.Value{.{ .string = msg }};

    const obj = TypeErrorConstructor(&ctor_args, &env).value.js_object;
    var args = [_]Types.Value{.{ .js_object = obj }};
    const result = ErrorToString(&args, &env);
    try testing.expectEqualStrings("TypeError: bad type", result.value.string);
}

test "ErrorToString returns void for empty args" {
    var env = try @import("../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    try testing.expect(ErrorToString(&[_]Types.Value{}, &env).value == .void);
}

test "Error() produces an object with the Error class identity markers" {
    // Locks down the shape that the evaluator's `instanceof Error` branch
    // (evaluator.zig, BinaryExpression::InstanceOf) reads: `@@type` must
    // equal "Error" so `e instanceof Error` returns true.
    var env = try @import("../evaluator.zig").Environment.init(testing.allocator, null);
    defer env.deinit();

    const obj = ErrorConstructor(&[_]Types.Value{}, &env).value.js_object;
    const tag = obj.properties.get("@@type") orelse return error.TestExpectedProperty;
    try testing.expect(tag == .string);
    try testing.expectEqualStrings("Error", tag.string);
    try testing.expectEqualStrings(
        "Error",
        obj.properties.get("@@subtype").?.string,
    );
}

test "ErrorObject is registered with single toString method" {
    try testing.expectEqualStrings("Error", ERROR_OBJECT.name);
    try testing.expect(ERROR_METHODS.len == 1);
    try testing.expectEqualStrings("toString", ERROR_METHODS[0].name);
}

test "ERROR_SUBTYPES lists the 7 ES2025 Error subclasses in canonical order" {
    try testing.expect(ERROR_SUBTYPES.len == 7);
    const expected = [_][]const u8{
        "Error",          "TypeError",      "RangeError",
        "ReferenceError", "SyntaxError",    "EvalError",
        "URIError",
    };
    for (expected, 0..) |name, i| try testing.expectEqualStrings(name, ERROR_SUBTYPES[i]);
}

test "throwError sets env.throw_hit + env.throw_value (.js_object) and returns .void" {
    const allocator = testing.allocator;
    var env = try @import("../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    // Baseline: env starts cleared.
    try testing.expect(!env.throw_hit);
    try testing.expect(env.throw_value == .void);

    const ret = throwError(&env, "RangeError", .{ .string = "Exponent must be positive" });
    try testing.expect(ret == .void);
    try testing.expect(env.throw_hit);

    // throw_value is the js_object built by makeErrorObject.
    try testing.expect(env.throw_value == .js_object);
    const obj = env.throw_value.js_object;
    try testing.expectEqualStrings("Error", obj.properties.get("@@type").?.string);
    try testing.expectEqualStrings("RangeError", obj.properties.get("@@subtype").?.string);
    try testing.expectEqualStrings("RangeError", obj.properties.get("name").?.string);
    try testing.expectEqualStrings("Exponent must be positive", obj.properties.get("message").?.string);
}

test "throwError with no message arg still produces a valid error object with empty message" {
    const allocator = testing.allocator;
    var env = try @import("../evaluator.zig").Environment.init(allocator, null);
    defer env.deinit();

    _ = throwError(&env, "TypeError", null);
    try testing.expect(env.throw_hit);
    try testing.expect(env.throw_value == .js_object);
    try testing.expectEqualStrings("TypeError", env.throw_value.js_object.properties.get("name").?.string);
    try testing.expectEqualStrings("TypeError", env.throw_value.js_object.properties.get("@@subtype").?.string);
    try testing.expectEqualStrings("", env.throw_value.js_object.properties.get("message").?.string);
}

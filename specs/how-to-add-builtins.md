# How to Add Builtin Methods to Lou

This guide explains the step-by-step process to add new builtin methods/functions to the Lou JavaScript interpreter.

## Architecture Overview

```
JS Code → Lexer → Parser → AST → VM → BuiltinObject.getMethod("name") → Your Zig function
```

When JS code calls `JSON.parse("...")`:
1. Parser creates a `MethodCall` AST node with `object=JSON`, `method="parse"`
2. VM looks up `JSON` in the builtin objects
3. Calls `JSON_OBJECT.getMethod("parse")` to find the Zig function
4. Executes the Zig function with the arguments

## Key Files

| File                                 | Purpose                                                     |
| --------------------------------------| -------------------------------------------------------------|
| `src/types/types.zig`                | Defines `BuiltinFn`, `BuiltinMethod`, `BuiltinObjectImpl`   |
| `src/builtins/builtinObjects.zig`    | Registry of all builtin objects (Array, Math, String, etc.) |
| `src/builtins/builtins.zig`          | Registry of constructor functions (Array, Set, Map)         |
| `src/builtins/<object>/<object>.zig` | Object definition with methods list                         |
| `src/builtins/<object>/<method>.zig` | Individual method implementation                            |

## Type Definitions

```zig
// src/types/types.zig

// Signature for ALL builtin functions
pub const BuiltinFn = *const fn ([]Value, *Environment) BuiltinResult;

// A method entry: name + function pointer
pub const BuiltinMethod = struct {
    name: []const u8,
    func: BuiltinFn,
};

// A builtin object: name + list of methods
pub const BuiltinObjectImpl = struct {
    name: []const u8,
    methods: []const BuiltinMethod,

    pub fn getMethod(self: *const BuiltinObjectImpl, method_name: []const u8) ?BuiltinFn {
        for (self.methods) |method| {
            if (std.mem.eql(u8, method.name, method_name)) {
                return method.func;
            }
        }
        return null;
    }
};

// Return type for builtin functions
pub const BuiltinResult = union(enum) {
    value: Value,
    void: void,
};
```

## Step-by-Step: Adding a Method to an Existing Object

**Example: Adding `JSON.parse`**

### Step 1: Create the method implementation file

Create `src/builtins/json/parse.zig`:

```zig
const std = @import("std");
const Types = @import("../../types/types.zig");
const Environment = @import("../../evaluator.zig").Environment;

/// JSON.parse(text, reviver?)
pub fn Parse(args: []const Types.Value, env: *Environment) Types.BuiltinResult {
    // args[0] = text (string to parse)
    // args[1] = reviver (optional function)
    if (args.len < 1) return .{ .value = .{ .void = {} } };

    const text = switch (args[0]) {
        .string => |s| s,
        else => return .{ .value = .{ .void = {} } },
    };

    // TODO: implement actual JSON parsing
    // For now, return void
    _ = text;
    _ = env;
    return .{ .value = .{ .void = {} } };
}
```

### Step 2: Import and register in the object file

Edit `src/builtins/json/json.zig`:

```zig
const Types = @import("../../types/types.zig");
const Stringify = @import("stringify.zig").Stringify;
const Parse = @import("parse.zig").Parse;  // ADD THIS

const JSON_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "stringify", .func = Stringify },
    .{ .name = "parse", .func = Parse },  // ADD THIS
};

pub const JSON_OBJECT = Types.BuiltinObjectImpl{
    .name = "JSON",
    .methods = &JSON_METHODS,
};
```

### Step 3: Register the object (if not already registered)

Check `src/builtins/builtinObjects.zig`. If the object is NOT in `BUILTIN_OBJECTS`, add it:

```zig
const JSON_OBJECT = @import("./json/json.zig").JSON_OBJECT;  // ADD IMPORT

pub const BUILTIN_OBJECTS = [_]*const Types.BuiltinObjectImpl{
    &CONSOLE_OBJECT,
    &ARRAY_OBJECT,
    &MATH_OBJECT,
    &STRING_OBJECT,
    &SET_OBJECT,
    &MAP_OBJECT,
    &OBJECT_OBJECT,
    &JSON_OBJECT,  // ADD THIS
};
```

### Step 4: Build and test

```bash
zig build
./zig-out/bin/lou run test.js
```

## Step-by-Step: Adding a Global Function

**Example: Adding `parseInt()`**

### Step 1: Create the implementation

Create `src/builtins/parseint.zig`:

```zig
const std = @import("std");
const Types = @import("../types/types.zig");

pub fn ParseInt(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .float = std.math.nan } };

    const str = switch (args[0]) {
        .string => |s| s,
        else => return .{ .value = .{ .float = std.math.nan } },
    };

    // Get radix (optional second arg)
    const radix: u10 = if (args.len >= 2) switch (args[1]) {
        .integer => |r| if (r >= 2 and r <= 36) @intCast(r) else 10,
        else => 10,
    } else 10;

    const result = std.fmt.parseInt(i64, str, radix) catch {
        return .{ .value = .{ .float = std.math.nan } };
    };
    return .{ .value = .{ .integer = result } };
}
```

### Step 2: Register in builtins.zig

Edit `src/builtins/builtins.zig`:

```zig
const ParseInt = @import("./parseint.zig").ParseInt;  // ADD IMPORT

const BUILTIN_FUNCTIONS = [_]struct { name: []const u8, func: Types.BuiltinFn }{
    .{ .name = "Array", .func = arrayConstructor },
    .{ .name = "Set", .func = SetConstructor },
    .{ .name = "Map", .func = MapConstructor },
    .{ .name = "parseInt", .func = ParseInt },  // ADD THIS
};
```

### Step 3: Build and test

```bash
zig build
echo 'console.log(parseInt("42"))' > test.js
./zig-out/bin/lou run test.js
```

## Working with Values

### Reading arguments

```zig
// String
const str = switch (args[0]) {
    .string => |s| s,  // s is []const u8
    else => return .{ .value = .{ .void = {} } },
};

// Integer
const num = switch (args[0]) {
    .integer => |i| i,  // i is i64
    else => return .{ .value = .{ .void = {} } },
};

// Float
const f = switch (args[0]) {
    .float => |f| f,  // f is f64
    else => return .{ .value = .{ .void = {} } },
};

// Boolean
const b = switch (args[0]) {
    .boolean => |b| b,  // b is bool
    else => return .{ .value = .{ .void = {} } },
};

// Array
const arr = switch (args[0]) {
    .array => |a| a,  // a is *ArrayObject
    else => return .{ .value = .{ .void = {} } },
};

// Object
const obj = switch (args[0]) {
    .js_object => |o| o,  // o is *ObjectValue
    else => return .{ .value = .{ .void = {} } },
};

// Null
if (args[0] == .null) { /* handle null */ }

// Undefined/Void
if (args[0] == .void) { /* handle undefined */ }
```

### Returning values

```zig
// Return string (must be owned by env)
const result_str = "hello";
return .{ .value = .{ .string = result_str } };

// Return integer
return .{ .value = .{ .integer = 42 } };

// Return float
return .{ .value = .{ .float = 3.14 } };

// Return boolean
return .{ .value = .{ .boolean = true } };

// Return null
return .{ .value = .{ .null = {} } };

// Return undefined
return .{ .value = .{ .void = {} } };

// Return array (must allocate)
const arr = ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
arr.elements.append(env.allocator, .{ .integer = 1 }) catch {};
return .{ .value = .{ .array = arr } };

// Return object (must allocate)
const obj = ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
obj.properties.put("key", .{ .string = "value" }) catch {};
return .{ .value = .{ .js_object = obj } };
```

### Returning allocated strings

For strings that need to be allocated (e.g., from formatting):

```zig
var buf = std.ArrayList(u8).initCapacity(env.allocator, 128) catch {
    return .{ .value = .{ .void = {} } };
};
defer buf.deinit(env.allocator);

// Build the string...
try buf.appendSlice(env.allocator, "hello");

// Transfer ownership to env
const result = buf.toOwnedSlice(env.allocator) catch {
    return .{ .value = .{ .void = {} } };
};
env.owned_strings.append(env.allocator, result) catch {};
return .{ .value = .{ .string = result } };
```

## Checking Argument Types

```zig
// Optional argument with default
const radix: i64 = if (args.len >= 2) switch (args[1]) {
    .integer => |r| r,
    .float => |f| @intFromFloat(f),
    else => 10,
} else 10;

// Type checking
fn validateArgs(args: []const Types.Value) bool {
    if (args.len < 1) return false;
    if (args[0] != .string) return false;
    if (args.len >= 2 and args[1] != .function) return false;
    return true;
}
```

## Complete Example: `Math.floor`

```zig
// src/builtins/math/floor.zig
const std = @import("std");
const Types = @import("../../types/types.zig");

pub fn Floor(args: []const Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .float = 0.0 } };
    return switch (args[0]) {
        .float => |f| .{ .value = .{ .float = @floor(f) } },
        .integer => |i| .{ .value = .{ .integer = i } },
        else => .{ .value = .{ .float = 0.0 } },
    };
}
```

```zig
// src/builtins/math/math.zig
const Types = @import("../../types/types.zig");
const Abs = @import("abs.zig").Abs;
const Floor = @import("floor.zig").Floor;  // ADD

const MATH_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "abs", .func = Abs },
    .{ .name = "floor", .func = Floor },  // ADD
};

pub const MATH_OBJECT = Types.BuiltinObjectImpl{
    .name = "Math",
    .methods = &MATH_METHODS,
};
```

## Quick Reference

| What you want to do | Files to modify |
|---------------------|-----------------|
| Add method to existing object | 1. Create `<method>.zig` 2. Import in `<object>.zig` 3. Add to methods array |
| Add new builtin object | 1. Create `<object>/<object>.zig` 2. Create method files 3. Add to `builtinObjects.zig` |
| Add global function | 1. Create `<func>.zig` 2. Add to `BUILTIN_FUNCTIONS` in `builtins.zig` |

## Common Pitfalls

1. **Forgetting to register**: Creating the file but not importing/adding it to the methods array
2. **Wrong signature**: Function must be `fn([]const Value, *Environment) BuiltinResult`
3. **Memory leaks**: Allocated strings must be tracked via `env.owned_strings`
4. **Not handling arg count**: Always check `args.len` before accessing `args[N]`
5. **Type mismatches**: Use `switch` on the Value union, not direct field access

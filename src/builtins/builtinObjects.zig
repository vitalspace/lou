const Types = @import("../types/types.zig");
const CONSOLE_OBJECT = @import("./console/console.zig").CONSOLE_OBJECT;
const ARRAY_OBJECT = @import("./array/array.zig").ARRAY_OBJECT;
const MATH_OBJECT = @import("./math/math.zig").MATH_OBJECT;
const STRING_OBJECT = @import("./string/string.zig").STRING_OBJECT;
const SET_OBJECT = @import("./set/set.zig").SET_OBJECT;
const MAP_OBJECT = @import("./map/map.zig").MAP_OBJECT;
const OBJECT_OBJECT = @import("./object/object.zig").OBJECT_OBJECT;
const BOOLEAN_OBJECT = @import("./boolean/boolean.zig").BOOLEAN_OBJECT;
const BIGINT_OBJECT = @import("./bigint/bigint.zig").BIGINT_OBJECT;
const DATE_OBJECT = @import("./date/date.zig").DATE_OBJECT;
const DISPOSABLE_STACK_OBJECT = @import("./disposable/disposable.zig").DISPOSABLE_STACK_OBJECT;
const ERROR_OBJECT = @import("./error.zig").ERROR_OBJECT;
const SYNTAX_ERROR_OBJECT = @import("./error.zig").SYNTAX_ERROR_OBJECT;
const TYPE_ERROR_OBJECT = @import("./error.zig").TYPE_ERROR_OBJECT;
const RANGE_ERROR_OBJECT = @import("./error.zig").RANGE_ERROR_OBJECT;
const REFERENCE_ERROR_OBJECT = @import("./error.zig").REFERENCE_ERROR_OBJECT;
const EVAL_ERROR_OBJECT = @import("./error.zig").EVAL_ERROR_OBJECT;
const URI_ERROR_OBJECT = @import("./error.zig").URI_ERROR_OBJECT;
const FINALIZATION_REGISTRY_OBJECT = @import("./finalization-registry.zig").FINALIZATION_REGISTRY_OBJECT;
const WEAKREF_OBJECT = @import("./weakref.zig").WEAKREF_OBJECT;
const WEAKMAP_OBJECT = @import("./weak/weakmap.zig").WEAKMAP_OBJECT;
const WEAKSET_OBJECT = @import("./weak/weakset.zig").WEAKSET_OBJECT;
const PROMISE_OBJECT = @import("./promise/promise.zig").PROMISE_OBJECT;
const REFLECT_OBJECT = @import("./reflect/reflect.zig").REFLECT_OBJECT;
const JSON_OBJECT = @import("./json/json.zig").JSON_OBJECT;
const intl = @import("./intl/intl.zig");
const NUMBER_OBJECT = @import("./number/number_object.zig").NUMBER_OBJECT;
const REGEXP_OBJECT = @import("./regex/regexp.zig").REGEXP_OBJECT;

pub const BUILTIN_OBJECTS = [_]*const Types.BuiltinObjectImpl{
    &CONSOLE_OBJECT,
    &ARRAY_OBJECT,
    &MATH_OBJECT,
    &STRING_OBJECT,
    &SET_OBJECT,
    &MAP_OBJECT,
    &OBJECT_OBJECT,
    &BOOLEAN_OBJECT,
    &BIGINT_OBJECT,
    &DATE_OBJECT,
    &DISPOSABLE_STACK_OBJECT,
    &ERROR_OBJECT,
    &SYNTAX_ERROR_OBJECT,
    &TYPE_ERROR_OBJECT,
    &RANGE_ERROR_OBJECT,
    &REFERENCE_ERROR_OBJECT,
    &EVAL_ERROR_OBJECT,
    &URI_ERROR_OBJECT,
    &FINALIZATION_REGISTRY_OBJECT,
    &WEAKREF_OBJECT,
    &WEAKMAP_OBJECT,
    &WEAKSET_OBJECT,
    &PROMISE_OBJECT,
    &REFLECT_OBJECT,
    &JSON_OBJECT,
    &intl.INTL_OBJECT,
    &intl.NUMBERFORMAT_OBJECT,
    &intl.DATETIMEFORMAT_OBJECT,
    &intl.COLLATOR_OBJECT,
    &NUMBER_OBJECT,
    &REGEXP_OBJECT,
};

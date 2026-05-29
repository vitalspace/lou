const std = @import("std");
const ast = @import("ast.zig");

/// Type checker pass. Runs after parsing, before evaluation.
/// Currently a skeleton that will be expanded to perform actual type checking.
/// For now, it validates that the AST is well-formed and prints a notice that
/// type checking is active (for .lou and .ts files).
pub const TypeChecker = struct {
    allocator: std.mem.Allocator,
    has_errors: bool,
    file_path: []const u8,

    pub const TypeError = struct {
        line: usize,
        column: usize,
        message: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) TypeChecker {
        return TypeChecker{
            .allocator = allocator,
            .has_errors = false,
            .file_path = file_path,
        };
    }

    pub fn check(self: *TypeChecker, _program: []const *ast.Node) !void {
        // TODO: Implement actual type checking logic (see specs/types/type-system-spec.md)
        // For now, this is a skeleton that accepts all programs.
        // Future phases will add:
        //   - Type annotation parsing
        //   - Type inference for literals and expressions
        //   - Type mismatch error reporting
        //   - Function parameter/return type checking
        //   - Compound type (Array, Object) checking
        _ = self;
        _ = _program;
    }
};
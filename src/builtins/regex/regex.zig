const std = @import("std");
const ast_mod = @import("engine/ast.zig");
const Ast = ast_mod.Ast;
const Parser = @import("engine/parser.zig").Parser;
const compiler = @import("engine/compiler.zig");
const vm = @import("engine/vm.zig");

pub const Flags = vm.Flags;
pub const VmFlags = Flags;
pub const ExecState = vm.ExecState;

pub const Regex = struct {
    allocator: std.mem.Allocator,
    vm: vm.Vm,
    named_groups: ?[]ast_mod.NamedGroupEntry,

    pub fn compile(allocator: std.mem.Allocator, pattern: []const u8, _: vm.Flags) !Regex {
        var parser = Parser.init(allocator, pattern);
        var ast = Ast.init(allocator);
        defer ast.deinit();

        try parser.parse(&ast);

        var program = try compiler.compile(allocator, &ast);
        errdefer {
            program.instructions.deinit(allocator);
            program.class_data.deinit(allocator);
        }

        // Take ownership of named groups by duplicating the data
        const named = if (ast.named_groups.items.len > 0) blk: {
            const entries = try allocator.dupe(ast_mod.NamedGroupEntry, ast.named_groups.items);
            for (entries, 0..) |*entry, i| {
                entry.*.name = try allocator.dupe(u8, ast.named_groups.items[i].name);
            }
            break :blk entries;
        } else null;

        const vm_instance = vm.Vm.init(allocator, program, parser.group_count, named);

        return Regex{
            .allocator = allocator,
            .vm = vm_instance,
            .named_groups = named,
        };
    }

    pub fn deinit(self: *Regex) void {
        self.vm.deinit();
        if (self.named_groups) |ng| {
            for (ng) |entry| {
                self.allocator.free(entry.name);
            }
            self.allocator.free(ng);
        }
    }

    pub fn testMatch(self: *const Regex, input: []const u8, flags: vm.Flags) !bool {
        return self.vm.testMatch(input, flags);
    }
};

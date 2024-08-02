const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

pub const GenerationDeleteCommand = struct {
    from: ?usize = null,
    to: ?usize = null,
    older_than: ?[]const u8 = null,
    keep: ArrayList(usize),
    gen_numbers: ArrayList(usize), // Positional args, not using an option

    const Self = @This();

    pub fn parseArgs(argv: *ArgIterator, parsed: *GenerationDeleteCommand) !?[]const u8 {
        _ = argv;
        _ = parsed;
        return null;
    }

    pub fn init(allocator: Allocator) Self {
        return GenerationDeleteCommand{
            .keep = ArrayList(usize).init(allocator),
            .gen_numbers = ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.keep.deinit();
        self.gen_numbers.deinit();
    }
};

const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;

const log = @import("../log.zig");

pub fn switchGeneration(allocator: Allocator, gen_number: usize, profile: []const u8) !void {
    _ = profile;
    _ = gen_number;
    _ = allocator;

    log.err("error: `nixos generation switch` is unimplemented", .{});

    return error.Unimplemented;
}

pub fn generationSwitchMain(allocator: Allocator, gen_number: usize, profile: ?[]const u8) u8 {
    const profile_dir = profile orelse "/nix/var/nix/profiles/system";

    switchGeneration(allocator, gen_number, profile_dir) catch unreachable;

    return 0;
}

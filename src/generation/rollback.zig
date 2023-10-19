const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const log = @import("../log.zig");

fn rollbackGeneration(allocator: Allocator, profile_dir: []const u8) !void {
    _ = allocator;
    _ = profile_dir;

    log.err("error: `nixos generation rollback` is unimplemented", .{});

    return error.Unimplemented;
}

pub fn generationRollbackMain(allocator: Allocator, profile: ?[]const u8) u8 {
    const profile_dir = profile orelse "/nix/var/nix/profiles/system";

    rollbackGeneration(allocator, profile_dir) catch unreachable;

    return 0;
}

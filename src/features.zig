//! Undocumented features subcommand for error reports and debugging.
//! This prints out the features, Zig version, and other information
//! that this was compiled with.

const std = @import("std");
const builtin = @import("builtin");
const opts = @import("options");

const io = std.io;
const mem = std.mem;

const Allocator = mem.Allocator;

fn print(out: anytype, comptime fmt: []const u8, args: anytype) void {
    out.print(fmt ++ "\n", args) catch return;
}

pub fn printFeatures() void {
    const stdout = io.getStdOut().writer();

    print(stdout, "nixos {s}\n", .{opts.version});
    print(stdout, "git rev: {s}", .{opts.git_rev});
    print(stdout, "zig version: {}", .{builtin.zig_version});
    print(stdout, "optimize mode: {s}\n", .{@tagName(builtin.mode)});
    print(stdout, "Enabled Features", .{});
    print(stdout, "----------------", .{});
    // TODO: should I print decls in an inline for loop? If so, how?
    print(stdout, "flake           :: {}", .{opts.flake});
    print(stdout, "nixpkgs_version :: {s}", .{opts.nixpkgs_version});
}

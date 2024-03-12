//! Undocumented features subcommand for error reports and debugging.
//! This prints out the features, Zig version, and other information
//! that this was compiled with.

const std = @import("std");
const builtin = @import("builtin");
const opts = @import("options");
const io = std.io;
const mem = std.mem;

const config = @import("config.zig");

const utils = @import("utils.zig");
const println = utils.println;

const Allocator = mem.Allocator;

pub fn printFeatures() void {
    const stdout = io.getStdOut().writer();

    println(stdout, "nixos {s}\n", .{opts.version});
    println(stdout, "git rev: {s}", .{opts.git_rev});
    println(stdout, "zig version: {}", .{builtin.zig_version});
    println(stdout, "optimize mode: {s}\n", .{@tagName(builtin.mode)});
    println(stdout, "Enabled Features", .{});
    println(stdout, "----------------", .{});
    // TODO: should I print decls in an inline for loop? If so, how?
    println(stdout, "flake           :: {}", .{opts.flake});
    println(stdout, "nixpkgs_version :: {s}", .{opts.nixpkgs_version});
}

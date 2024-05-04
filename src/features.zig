//! Undocumented features subcommand for error reports and debugging.
//! This prints out the features, Zig version, and other information
//! that this was compiled with.

const std = @import("std");
const builtin = @import("builtin");
const opts = @import("options");
const io = std.io;
const mem = std.mem;
const Allocator = mem.Allocator;

const config = @import("config.zig");

const utils = @import("utils.zig");
const println = utils.println;

const nix = @import("nix");

pub fn printFeatures() void {
    const stdout = io.getStdOut().writer();

    println(stdout, "nixos {s}\n", .{opts.version});
    println(stdout, "git rev: {s}", .{opts.git_rev});
    println(stdout, "zig version: {}", .{builtin.zig_version});
    println(stdout, "optimize mode: {s}", .{@tagName(builtin.mode)});
    println(stdout, "bundled nix version: {s}\n", .{nix.util.version()});
    println(stdout, "Enabled Features", .{});
    println(stdout, "----------------", .{});

    println(stdout, "flake           :: {}", .{opts.flake});
    println(stdout, "nixpkgs_version :: {s}", .{opts.nixpkgs_version});
}

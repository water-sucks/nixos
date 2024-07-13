//! A convenient shorthand for dropping into a Nix REPL with
//! all of your system configuration parameters loaded and
//! ready to go.

const std = @import("std");
const opts = @import("options");
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const posix = std.posix;
const process = std.process;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;
const ArgIterator = process.ArgIterator;

const argparse = @import("argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argError = argparse.argError;
const argIs = argparse.argIs;
const getNextArgs = argparse.getNextArgs;

const log = @import("log.zig");

const utils = @import("utils.zig");
const FlakeRef = utils.FlakeRef;
const fileExistsAbsolute = utils.fileExistsAbsolute;

pub const ReplCommand = struct {
    flake: ?[]const u8 = null,
    includes: ArrayList([]const u8),

    const Self = @This();

    pub const usage =
        \\Start a Nix REPL with current system's configuration loaded.
        \\
        \\Usage:
        \\
    (if (opts.flake)
        \\    nixos repl [FLAKE-REF] [options]
        \\
        \\Arguments:
        \\    [FLAKE-REF]    Flake ref to build configuration from (default: $NIXOS_CONFIG)
    else
        \\    nixos repl [options]
        \\
    ) ++
        \\
        \\Options:
        \\    -I, --include <PATH>    Add a path value to the Nix search path
        \\
    ;

    pub fn init(allocator: Allocator) Self {
        return ReplCommand{
            .includes = ArrayList([]const u8).init(allocator),
        };
    }

    pub fn parseArgs(argv: *ArgIterator, parsed: *ReplCommand) !?[]const u8 {
        var next_arg = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--include", "-I")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                try parsed.includes.append(next);
            } else {
                if (opts.flake and parsed.flake == null) {
                    parsed.flake = arg;
                } else {
                    return arg;
                }
            }

            next_arg = argv.next();
        }

        return null;
    }

    pub fn deinit(self: *Self) void {
        self.includes.deinit();
    }
};

pub const ReplError = error{ ConfigurationNotFound, ReplExecError } || Allocator.Error;

const flake_repl_expr =
    \\let
    \\  flake = builtins.getFlake "{s}";
    \\  system = flake.nixosConfigurations."{s}";
    \\in (flake
    \\  // {{
    \\    inherit (system) config lib options pkgs;
    \\  }})
    \\
;

fn execFlakeRepl(allocator: Allocator, ref: FlakeRef, includes: []const []const u8) !void {
    const expr = try fmt.allocPrint(allocator, flake_repl_expr, .{ ref.uri, ref.system });
    defer allocator.free(expr);

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix", "repl", "--expr", expr });
    for (includes) |path| {
        try argv.appendSlice(&.{ "-I", path });
    }

    return process.execve(allocator, argv.items, null);
}

const legacy_repl_expr =
    \\let
    \\  system = import <nixpkgs/nixos> {};
    \\in {
    \\  inherit (system) config lib options pkgs;
    \\}
    \\
;

fn execLegacyRepl(allocator: Allocator, includes: []const []const u8, impure: bool) !void {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix", "repl", "--expr", legacy_repl_expr });
    for (includes) |path| {
        try argv.appendSlice(&.{ "-I", path });
    }

    // This is so that Nix can read environment variables, for things
    // like NIXOS_CONFIG to be picked up.
    if (impure) {
        try argv.append("--impure");
    }

    return process.execve(allocator, argv.items, null);
}

fn repl(allocator: Allocator, args: ReplCommand) ReplError!void {
    if (opts.flake) {
        var hostname_buf: [posix.HOST_NAME_MAX]u8 = undefined;
        var flake_ref = if (args.flake) |flake|
            FlakeRef.fromSlice(flake)
        else
            utils.findFlakeRef() catch return ReplError.ConfigurationNotFound;
        flake_ref.inferSystemNameIfNeeded(&hostname_buf) catch return ReplError.ConfigurationNotFound;

        execFlakeRepl(allocator, flake_ref, args.includes.items) catch return ReplError.ReplExecError;
    } else {
        utils.verifyLegacyConfigurationExists(allocator, false) catch return ReplError.ConfigurationNotFound;
        execLegacyRepl(allocator, args.includes.items, posix.getenv("NIXOS_CONFIG") != null) catch return ReplError.ReplExecError;
    }
}

pub fn replMain(allocator: Allocator, args: ReplCommand) u8 {
    repl(allocator, args) catch |err| {
        return switch (err) {
            ReplError.ReplExecError => 1,
            ReplError.ConfigurationNotFound => 4,
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
        };
    };
    return 0;
}

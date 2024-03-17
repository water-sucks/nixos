//! A convenient shorthand for dropping into a Nix REPL with
//! all of your system configuration parameters loaded and
//! ready to go.

const std = @import("std");
const opts = @import("options");
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const os = std.os;
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

pub const ReplArgs = struct {
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
        return ReplArgs{
            .includes = ArrayList([]const u8).init(allocator),
        };
    }

    pub fn parseArgs(allocator: Allocator, argv: *ArgIterator) !ReplArgs {
        var result = ReplArgs.init(allocator);
        errdefer result.deinit();

        var next_arg = argv.next();

        while (next_arg) |arg| {
            if (argIs(arg, "--include", "-I")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                try result.includes.append(next);
            } else {
                if (argparse.isFlag(arg)) {
                    argError("unrecognised flag '{s}'", .{arg});
                    return ArgParseError.InvalidArgument;
                } else if (opts.flake and result.flake == null) {
                    result.flake = arg;
                } else {
                    argError("argument '{s}' is not valid in this context", .{arg});
                    return ArgParseError.InvalidArgument;
                }
            }

            next_arg = argv.next();
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.includes.deinit();
    }
};

pub const ReplError = error{ ConfigurationNotFound, ReplExecError } || Allocator.Error;

var hostname_buffer: [os.HOST_NAME_MAX]u8 = undefined;

fn findFlakeRef(allocator: Allocator) !FlakeRef {
    var flake_ref: FlakeRef = undefined;
    const nixos_config = os.getenv("NIXOS_CONFIG") orelse {
        log.err("NIXOS_CONFIG is unset, unable to find configuration", .{});
        return ReplError.ConfigurationNotFound;
    };

    const nixos_config_is_flake = blk: {
        const filename = try fs.path.join(allocator, &.{ nixos_config, "flake.nix" });
        defer allocator.free(filename);

        break :blk fileExistsAbsolute(filename);
    };

    if (!nixos_config_is_flake) {
        log.err("configuration at {s} is not a flake", .{nixos_config});
        return ReplError.ConfigurationNotFound;
    }

    flake_ref = FlakeRef.fromSlice(nixos_config);
    if (flake_ref.system.len == 0) {
        flake_ref.system = os.gethostname(&hostname_buffer) catch {
            log.err("unable to determine hostname", .{});
            return ReplError.ConfigurationNotFound;
        };
    }
    return flake_ref;
}

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

// Verify legacy configuration exists, if needed (no need to store location,
// because it is implicitly used by Nix REPL expression)
fn legacyConfigExists(allocator: Allocator) !void {
    if (os.getenv("NIXOS_CONFIG")) |dir| {
        const filename = try fs.path.join(allocator, &.{ dir, "default.nix" });
        defer allocator.free(filename);
        if (!fileExistsAbsolute(filename)) {
            log.err("no configuration found, expected {s} to exist", .{filename});
            return ReplError.ConfigurationNotFound;
        }
    } else {
        const nix_path = os.getenv("NIX_PATH") orelse "";
        var paths = mem.tokenize(u8, nix_path, ":");

        var configuration: ?[]const u8 = null;
        while (paths.next()) |path| {
            var kv = mem.tokenize(u8, path, "=");
            if (mem.eql(u8, kv.next() orelse "", "nixos-config")) {
                configuration = kv.next();
                break;
            }
        }

        if (configuration == null) {
            log.err("no configuration found, expected 'nixos-config' attribute to exist in NIX_PATH", .{});
            return ReplError.ConfigurationNotFound;
        }
    }
}

const legacy_repl_expr =
    \\let
    \\  system = import <nixpkgs/nixos> {};
    \\in {{
    \\  inherit (system) config lib options pkgs;
    \\}}
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

fn repl(allocator: Allocator, args: ReplArgs) ReplError!void {
    if (opts.flake) {
        const flake_ref = if (args.flake) |flake|
            FlakeRef.fromSlice(flake)
        else
            try findFlakeRef(allocator);
        execFlakeRepl(allocator, flake_ref, args.includes.items) catch return ReplError.ReplExecError;
    } else {
        try legacyConfigExists(allocator);
        execLegacyRepl(allocator, args.includes.items, os.getenv("NIXOS_CONFIG") != null) catch return ReplError.ReplExecError;
    }
}

pub fn replMain(allocator: Allocator, args: ReplArgs) u8 {
    repl(allocator, args) catch |err| {
        return switch (err) {
            ReplError.ReplExecError => 1,
            ReplError.ConfigurationNotFound => 4,
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue");
                return 1;
            },
            else => 1,
        };
    };
    return 0;
}

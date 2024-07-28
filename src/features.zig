//! Features subcommand for error reports and debugging.
//! This prints out the features, Zig version, and other information
//! that this was compiled with.

const std = @import("std");
const builtin = @import("builtin");
const opts = @import("options");
const json = std.json;
const io = std.io;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argError = argparse.argError;
const argIs = argparse.argIs;
const getNextArgs = argparse.getNextArgs;

const config = @import("config.zig");

const log = @import("log.zig");

const utils = @import("utils.zig");
const println = utils.println;

pub const FeaturesCommand = struct {
    json: bool = false,

    const usage =
        \\Show metadata about this application and configured options.
        \\
        \\Usage:
        \\    nixos features [options]
        \\
        \\Options:
        \\    -h, --help    Show this help menu
        \\    -j, --json    Output information in JSON format
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator, parsed: *FeaturesCommand) !?[]const u8 {
        var next_arg = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--json", "-j")) {
                parsed.json = true;
            } else {
                return arg;
            }

            next_arg = argv.next();
        }

        return null;
    }
};

pub fn printFeatures(args: FeaturesCommand) void {
    const stdout = io.getStdOut().writer();

    if (args.json) {
        const obj = .{
            .version = opts.version,
            .git_rev = opts.git_rev,
            .zig_version = builtin.zig_version,
            .optimisation_mode = @tagName(builtin.mode),
            .options = .{
                .flake = opts.flake,
                .nixpkgs_version = opts.nixpkgs_version,
            },
        };
        json.stringify(obj, .{ .whitespace = .indent_2 }, stdout) catch unreachable;
        println(stdout, "", .{});
        return;
    }

    println(stdout, "nixos {s}\n", .{opts.version});
    println(stdout, "git rev: {s}", .{opts.git_rev});
    println(stdout, "zig version: {}", .{builtin.zig_version});
    println(stdout, "optimisation mode: {s}\n", .{@tagName(builtin.mode)});

    println(stdout, "Compilation Options", .{});
    println(stdout, "-------------------", .{});

    println(stdout, "flake           :: {}", .{opts.flake});
    println(stdout, "nixpkgs_version :: {s}", .{opts.nixpkgs_version});
}

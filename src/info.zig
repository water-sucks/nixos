const std = @import("std");
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const math = std.math;
const Allocator = mem.Allocator;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("argparse.zig");
const argIs = argparse.argIs;
const argError = argparse.argError;
const ArgParseError = argparse.ArgParseError;

const Constants = @import("constants.zig");

const log = @import("log.zig");

const utils = @import("utils.zig");
const readFile = utils.readFile;
const fileExistsAbsolute = utils.fileExistsAbsolute;
const println = utils.println;

const InfoError = error{} || Allocator.Error;

pub const InfoCommand = struct {
    config_rev: bool = false,
    json: bool = false,
    markdown: bool = false,
    nixpkgs_rev: bool = false,
    version: bool = false,

    const usage =
        \\Show information about the currently running NixOS generation.
        \\
        \\Usage:
        \\    nixos info [options]
        \\
        \\Options:
        \\    -c  --config-rev     Configuration revision this system was built from
        \\    -h, --help           Show this help menu
        \\    -j, --json           Format output as JSON
        \\    -m, --markdown       Format output as Markdown
        \\    -n  --nixpkgs-rev    Nixpkgs revision this system was built using
        \\    -v, --version        NixOS version this generation is currently running
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator, parsed: *InfoCommand) !?[]const u8 {
        while (argv.next()) |arg| {
            if (argIs(arg, "--config-rev", "-c")) {
                parsed.config_rev = true;
            } else if (argIs(arg, "--json", "-j")) {
                parsed.json = true;
            } else if (argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--markdown", "-m")) {
                parsed.markdown = true;
            } else if (argIs(arg, "--nixpkgs-rev", "-n")) {
                parsed.nixpkgs_rev = true;
            } else if (argIs(arg, "--version", "-v")) {
                parsed.version = true;
            } else {
                return arg;
            }
        }

        return null;
    }
};

fn info(allocator: Allocator, args: InfoCommand) InfoError!void {
    var current_system_dir = fs.openDirAbsolute("/run/current-system", .{}) catch |err| {
        log.err("unable to open current system dir: {s}", .{@errorName(err)});
        return InfoError.OutOfMemory;
    };
    defer current_system_dir.close();

    var generation_info = utils.generation.GenerationMetadata.getGenerationInfo(allocator, current_system_dir, null) catch return InfoError.OutOfMemory;
    defer generation_info.deinit();

    const stdout = io.getStdOut().writer();

    if (args.json) {
        std.json.stringify(generation_info, .{
            .whitespace = .indent_2,
        }, stdout) catch unreachable;
        println(stdout, "", .{});
        return;
    }

    if (args.markdown) {
        println(stdout,
            \\ - nixos version: `{?s}`
            \\ - nixpkgs revision: `{?s}`
            \\ - configuration revision: `{?s}`
        , .{
            generation_info.nixos_version,
            generation_info.nixpkgs_revision,
            generation_info.configuration_revision,
        });
        return;
    }

    // If no args are filled, just print the version and exit
    if (!args.config_rev and !args.nixpkgs_rev and !args.version) {
        println(stdout, "{s}", .{generation_info.nixos_version orelse "unknown"});
        return;
    }

    if (args.version) {
        println(stdout, "{s}", .{generation_info.nixos_version orelse "unknown"});
    }

    if (args.config_rev) {
        println(stdout, "{s}", .{generation_info.configuration_revision orelse "unknown"});
    }

    if (args.nixpkgs_rev) {
        println(stdout, "{s}", .{generation_info.nixpkgs_revision orelse "unknown"});
    }
}

pub fn infoMain(allocator: Allocator, args: InfoCommand) u8 {
    if (!fileExistsAbsolute(Constants.etc_nixos)) {
        log.err("the generation command is unsupported on non-NixOS systems", .{});
        return 3;
    }

    info(allocator, args) catch |err| {
        switch (err) {
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
        }
    };
    return 0;
}

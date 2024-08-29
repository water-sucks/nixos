const std = @import("std");
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const math = std.math;
const posix = std.posix;
const Allocator = mem.Allocator;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("argparse.zig");
const argIs = argparse.argIs;
const argError = argparse.argError;
const ArgParseError = argparse.ArgParseError;

const Constants = @import("constants.zig");

const log = @import("log.zig");

const utils = @import("utils.zig");
const GenerationMetadata = utils.generation.GenerationMetadata;
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
        \\    -h, --help       Show this help menu
        \\    -j, --json       Format output as JSON
        \\    -m, --markdown   Format output as Markdown for reporting
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator, parsed: *InfoCommand) !?[]const u8 {
        while (argv.next()) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--json", "-j")) {
                parsed.json = true;
            } else if (argIs(arg, "--markdown", "-m")) {
                parsed.markdown = true;
            } else {
                return arg;
            }
        }

        return null;
    }
};

// FIXME: this does not work with multiple profiles, I'll rework this
// later, because it's rare to see people using different profiles.
fn findCurrentGenerationNumber() ?usize {
    var path_buf: [posix.PATH_MAX]u8 = undefined;
    var path_buf2: [posix.PATH_MAX]u8 = undefined;

    // In order to get the generation number for most situations, we
    // can do a `readlink` on /run/current-system and make sure it is
    // the same as one of the profiles.

    const current_system_drv = posix.readlink(Constants.current_system, &path_buf) catch |err| {
        log.warn("unable to open " ++ Constants.nix_profiles ++ ": {s}", .{@errorName(err)});
        return null;
    };

    var system_dir = fs.openDirAbsolute(Constants.nix_profiles, .{ .iterate = true }) catch |err| blk: {
        log.warn("unable to open " ++ Constants.nix_profiles ++ ": {s}", .{@errorName(err)});
        break :blk null;
    };
    if (system_dir) |*dir| {
        defer dir.close();
        var iter = dir.iterate();
        while (true) {
            const entry = iter.next() catch continue orelse break;

            if (!mem.endsWith(u8, entry.name, "-link")) {
                continue;
            }

            const link = dir.readLink(entry.name, &path_buf2) catch continue;

            if (mem.eql(u8, link, current_system_drv)) {
                var it = mem.tokenizeScalar(u8, entry.name, '-');
                var possible_number_slice: ?[]const u8 = it.next();

                while (true) {
                    const next = it.next();
                    if (next == null) {
                        possible_number_slice = null;
                        break;
                    }

                    if (mem.eql(u8, next.?, "link") and it.rest().len == 0) {
                        break;
                    }

                    possible_number_slice = next.?;
                }

                if (possible_number_slice) |number_str| {
                    const gen_number = std.fmt.parseInt(usize, number_str, 10) catch continue;
                    return gen_number;
                }
            }
        }
    }

    return null;
}

fn info(allocator: Allocator, args: InfoCommand) InfoError!void {
    var current_system_dir = fs.openDirAbsolute(Constants.current_system, .{}) catch |err| {
        log.err("unable to open /run/current-system: {s}", .{@errorName(err)});
        return InfoError.OutOfMemory;
    };
    defer current_system_dir.close();

    var generation_info = GenerationMetadata.getGenerationInfo(allocator, current_system_dir, null) catch return InfoError.OutOfMemory;
    defer generation_info.deinit();
    // By definition, always the current generation.
    generation_info.current = true;
    generation_info.generation = findCurrentGenerationNumber();

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
            \\ - kernel version: `{?s}`
        , .{
            generation_info.nixos_version,
            generation_info.nixpkgs_revision,
            generation_info.kernel_version,
        });
        return;
    }

    generation_info.prettyPrint(.{
        .show_current_marker = false,
    }, stdout) catch unreachable;
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

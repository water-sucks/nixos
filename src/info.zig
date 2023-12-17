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

const GenerationInfo = @import("generation.zig").GenerationInfo;

const log = @import("log.zig");

const utils = @import("utils.zig");
const readFile = utils.readFile;
const fileExistsAbsolute = utils.fileExistsAbsolute;

const InfoError = error{} || Allocator.Error;

pub const InfoArgs = struct {
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

    pub fn parseArgs(args: *ArgIterator) !InfoArgs {
        var result = InfoArgs{};

        // TODO: should this ignore conflicting args,
        // or take the first argument and run with it?
        var next_arg: ?[]const u8 = args.next();
        if (next_arg) |arg| {
            if (argIs(arg, "--config-rev", "-c")) {
                result.config_rev = true;
            } else if (argIs(arg, "--json", "-j")) {
                result.json = true;
            } else if (argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--markdown", "-m")) {
                result.markdown = true;
            } else if (argIs(arg, "--nixpkgs-rev", "-n")) {
                result.nixpkgs_rev = true;
            } else if (argIs(arg, "--version", "-v")) {
                result.version = true;
            } else {
                if (argparse.isFlag(arg)) {
                    argError("unrecognised flag '{s}'", .{arg});
                } else {
                    argError("argument '{s}' is not valid in this context", .{arg});
                }
                return ArgParseError.InvalidArgument;
            }
        }

        return result;
    }
};

fn info(allocator: Allocator, args: InfoArgs) InfoError!void {
    const parsed_version_contents = blk: {
        const filename = Constants.current_system ++ "/nixos-version.json";

        const contents = readFile(allocator, filename) catch break :blk null;
        defer allocator.free(contents);

        break :blk std.json.parseFromSlice(GenerationInfo, allocator, contents, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }) catch null;
    };
    defer {
        if (parsed_version_contents) |contents| contents.deinit();
    }

    const stdout = io.getStdOut().writer();

    var version_info = if (parsed_version_contents) |parsed|
        parsed.value
    else
        GenerationInfo{};

    // Find version from os-release PRETTY_NAME field if not known
    const nixos_version = if (version_info.nixosVersion == null) blk: {
        const filename = Constants.current_system ++ "/etc/os-release";

        const os_release = readFile(allocator, filename) catch break :blk null;
        defer allocator.free(os_release);

        var lines = mem.tokenizeScalar(u8, os_release, '\n');
        while (lines.next()) |line| {
            if (mem.startsWith(u8, line, "PRETTY_NAME=")) {
                break :blk try allocator.dupe(u8, line[13..(line.len - 1)]);
            }
        }

        break :blk null;
    } else null;
    defer if (nixos_version) |v| allocator.free(v);

    // Fill in unfilled fields with "unknown",
    // it's not very fun to determine otherwise
    if (version_info.nixosVersion == null) {
        version_info.nixosVersion = nixos_version orelse "unknown";
    }

    if (version_info.configurationRevision == null) {
        version_info.configurationRevision = "unknown";
    }

    if (version_info.nixpkgsRevision == null) {
        version_info.nixpkgsRevision = "unknown";
    }

    if (args.nixpkgs_rev) {
        stdout.print("{s}\n", .{version_info.nixpkgsRevision.?}) catch unreachable;
    } else if (args.nixpkgs_rev) {
        stdout.print("{s}\n", .{version_info.nixpkgsRevision.?}) catch unreachable;
    } else if (args.json) {
        std.json.stringify(version_info, .{ .whitespace = .indent_2 }, stdout) catch unreachable;
        stdout.print("\n", .{}) catch unreachable;
    } else if (args.markdown) {
        stdout.print(
            \\ - nixos version: `{s}`
            \\ - nixpkgs revision: `{s}`
            \\ - configuration revision: `{s}`
            \\
        , .{
            version_info.nixosVersion.?,
            version_info.nixpkgsRevision.?,
            version_info.configurationRevision.?,
        }) catch unreachable;
    } else {
        stdout.print("{s}\n", .{version_info.nixosVersion.?}) catch unreachable;
    }
}

pub fn infoMain(allocator: Allocator, args: InfoArgs) u8 {
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

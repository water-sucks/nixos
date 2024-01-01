const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("../argparse.zig");
const argError = argparse.argError;
const argIs = argparse.argIs;
const getNextArgs = argparse.getNextArgs;
const ArgParseError = argparse.ArgParseError;

const Constants = @import("../constants.zig");

const log = @import("../log.zig");

const utils = @import("../utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;
const runCmd = utils.runCmd;

pub const GenerationDiffArgs = struct {
    before: usize = undefined,
    after: usize = undefined,

    const usage =
        \\Display what packages differ between two generations.
        \\
        \\Usage:
        \\    nixos generation diff <BEFORE> <AFTER>
        \\
        \\Arguments:
        \\    <BEFORE>:    Number of first generation
        \\    <AFTER>:     Number of second generation
    ;

    pub fn parseArgs(argv: *ArgIterator) !GenerationDiffArgs {
        var result: GenerationDiffArgs = GenerationDiffArgs{};

        var before = argv.next() orelse {
            argError("missing required argument <BEFORE>", .{});
            return ArgParseError.MissingRequiredArgument;
        };
        result.before = std.fmt.parseInt(usize, before, 10) catch {
            argError("'{s}' is not a valid generation number", .{before});
            return ArgParseError.InvalidArgument;
        };

        var next = argv.next() orelse {
            argError("missing required argument <AFTER>", .{});
            return ArgParseError.MissingRequiredArgument;
        };

        result.after = std.fmt.parseInt(usize, next, 10) catch {
            argError("'{s}' is not a valid generation number", .{next});
            return ArgParseError.InvalidArgument;
        };

        if (argv.next()) |arg| {
            argError("'{s}' is not valid in this context", .{arg});
            return ArgParseError.InvalidArgument;
        }

        return result;
    }
};

const GenerationDiffError = error{CommandFailed} || Allocator.Error;

var exit_status: u8 = 0;

fn nixDiff(allocator: Allocator, before: []const u8, after: []const u8) !void {
    const argv: []const []const u8 = &.{
        "nix",
        "store",
        "diff-closures",
        before,
        after,
    };

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
        .stdout_type = .Inherit,
    }) catch return GenerationDiffError.CommandFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return GenerationDiffError.CommandFailed;
    }
}

fn generationDiff(allocator: Allocator, args: GenerationDiffArgs, profile_name: []const u8) !void {
    const base_profile_dirname = if (mem.eql(u8, profile_name, "system"))
        Constants.nix_profiles
    else
        Constants.nix_system_profiles;

    const before_dirname = try fmt.allocPrint(allocator, "{s}/{s}-{d}-link", .{ base_profile_dirname, profile_name, args.before });
    defer allocator.free(before_dirname);

    const after_dirname = try fmt.allocPrint(allocator, "{s}/{s}-{d}-link", .{ base_profile_dirname, profile_name, args.after });
    defer allocator.free(after_dirname);

    // TODO: replace with custom libnixstore implementation
    try nixDiff(allocator, before_dirname, after_dirname);
}

pub fn generationDiffMain(allocator: Allocator, args: GenerationDiffArgs, profile: ?[]const u8) u8 {
    const profile_name = profile orelse "system";

    generationDiff(allocator, args, profile_name) catch |err| {
        switch (err) {
            GenerationDiffError.CommandFailed => return if (exit_status != 0) exit_status else 1,
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
        }
    };

    return 0;
}

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

pub const GenerationDiffCommand = struct {
    before: usize = 0,
    after: usize = 0,

    const usage =
        \\Display what packages differ between two generations.
        \\
        \\Usage:
        \\    nixos generation diff <BEFORE> <AFTER>
        \\
        \\Arguments:
        \\    <BEFORE>:    Number of first generation
        \\    <AFTER>:     Number of second generation
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator, parsed: *GenerationDiffCommand) !?[]const u8 {
        var before_parsed = false;
        var after_parsed = false;

        while (argv.next()) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
                return ArgParseError.HelpInvoked;
            }

            if (argparse.isFlag(arg)) {
                return arg;
            }

            if (!before_parsed) {
                parsed.before = std.fmt.parseInt(usize, arg, 10) catch {
                    argError("'{s}' is not a valid generation number", .{arg});
                    return ArgParseError.InvalidArgument;
                };
                before_parsed = true;
            } else if (!after_parsed) {
                parsed.after = std.fmt.parseInt(usize, arg, 10) catch {
                    argError("'{s}' is not a valid generation number", .{arg});
                    return ArgParseError.InvalidArgument;
                };
                after_parsed = true;
            } else {
                argError("argument '{s}' is not valid in this context", .{arg});
                return ArgParseError.InvalidArgument;
            }
        }

        if (parsed.before == 0) {
            argError("missing required argument <BEFORE>", .{});
            return ArgParseError.MissingRequiredArgument;
        }
        if (parsed.after == 0) {
            argError("missing required argument <AFTER>", .{});
            return ArgParseError.MissingRequiredArgument;
        }

        return null;
    }
};

const GenerationDiffError = error{CommandFailed} || Allocator.Error;

var exit_status: u8 = 0;

fn generationDiff(allocator: Allocator, args: GenerationDiffCommand, profile_name: []const u8) !void {
    const base_profile_dirname = if (mem.eql(u8, profile_name, "system"))
        Constants.nix_profiles
    else
        Constants.nix_system_profiles;

    const before_dirname = try fmt.allocPrint(allocator, "{s}/{s}-{d}-link", .{ base_profile_dirname, profile_name, args.before });
    defer allocator.free(before_dirname);

    const after_dirname = try fmt.allocPrint(allocator, "{s}/{s}-{d}-link", .{ base_profile_dirname, profile_name, args.after });
    defer allocator.free(after_dirname);

    const status = utils.generation.diff(allocator, before_dirname, after_dirname, false) catch |err| {
        log.err("diff command failed to run: {s}", .{@errorName(err)});
        return GenerationDiffError.CommandFailed;
    };
    if (status != 0) {
        exit_status = status;
        return GenerationDiffError.CommandFailed;
    }
}

pub fn generationDiffMain(allocator: Allocator, args: GenerationDiffCommand, profile: ?[]const u8) u8 {
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

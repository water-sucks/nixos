const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argIs = argparse.argIs;
const isFlag = argparse.isFlag;
const argError = argparse.argError;

const Constants = @import("constants.zig");

const log = @import("log.zig");

const utils = @import("utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;

const generationDiff = @import("generation/diff.zig");
const generationList = @import("generation/list.zig");
const generationRollback = @import("generation/rollback.zig");
const generationSwitch = @import("generation/switch.zig");
const GenerationDiffArgs = generationDiff.GenerationDiffArgs;
const GenerationListArgs = generationList.GenerationListArgs;
const GenerationSwitchArgs = generationSwitch.GenerationSwitchArgs;
const GenerationRollbackArgs = generationRollback.GenerationRollbackArgs;

const GenerationError = error{};

pub const GenerationArgs = struct {
    // System profile directory to use
    profile: ?[]const u8 = null,
    // Subcommand that will be ran
    subcommand: ?GenerationCommand = null,

    const GenerationCommand = union(enum) {
        diff: GenerationDiffArgs,
        list: GenerationListArgs,
        rollback: GenerationRollbackArgs,
        @"switch": GenerationSwitchArgs,
    };

    pub const usage =
        \\Manage NixOS generations on this machine.
        \\
        \\Usage:
        \\    nixos generation [options] <COMMAND>
        \\
        \\Commands:
        \\    diff <FROM> <TO>    Show what packages were changed between two generations
        \\    list                List all NixOS generations in current profile
        \\    rollback            Activate the previous generation
        \\    switch <NUMBER>     Activate the generation with the given number
        \\
        \\Options:
        \\    -h, --help        Show this help menu
        \\    -p, --profile     System profile to use
        \\
        \\For more information about a subcommand, add --help after.
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator) !GenerationArgs {
        var result: GenerationArgs = GenerationArgs{};

        var selected_subcommand = false;

        var next_arg: ?[]const u8 = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--profile", "-p")) {
                result.profile = (try argparse.getNextArgs(argv, arg, 1))[0];
            } else if (argparse.isFlag(arg)) {
                argError("unrecognised flag '{s}'", .{arg});
                return ArgParseError.InvalidArgument;
            } else if (!selected_subcommand) {
                if (mem.eql(u8, arg, "diff")) {
                    result.subcommand = .{ .diff = GenerationDiffArgs{} };
                } else if (mem.eql(u8, arg, "list")) {
                    result.subcommand = .{ .list = GenerationListArgs{} };
                } else if (mem.eql(u8, arg, "rollback")) {
                    result.subcommand = .{ .rollback = GenerationRollbackArgs{} };
                } else if (mem.eql(u8, arg, "switch")) {
                    result.subcommand = .{ .@"switch" = GenerationSwitchArgs{} };
                } else {
                    argError("unknown subcommand '{s}'", .{arg});
                    return ArgParseError.InvalidSubcommand;
                }
                selected_subcommand = true;
            }

            next_arg = if (selected_subcommand) switch (result.subcommand.?) {
                .diff => |*sub_args| try GenerationDiffArgs.parseArgs(argv, sub_args),
                .list => |*sub_args| try GenerationListArgs.parseArgs(argv, sub_args),
                .rollback => |*sub_args| try GenerationRollbackArgs.parseArgs(argv, sub_args),
                .@"switch" => |*sub_args| try GenerationSwitchArgs.parseArgs(argv, sub_args),
            } else argv.next();
        }

        if (!selected_subcommand) {
            argError("no subcommand specified", .{});
            return ArgParseError.MissingRequiredArgument;
        }

        // NOTE: DO NOT REMOVE THIS! This serves as extra validation in case
        // an extra argument has not been passed correctly.
        _ = switch (result.subcommand.?) {
            .diff => |*sub_args| try GenerationDiffArgs.parseArgs(argv, sub_args),
            .list => |*sub_args| try GenerationListArgs.parseArgs(argv, sub_args),
            .rollback => |*sub_args| try GenerationRollbackArgs.parseArgs(argv, sub_args),
            .@"switch" => |*sub_args| try GenerationSwitchArgs.parseArgs(argv, sub_args),
        };

        return result;
    }
};

/// This will be parsed as JSON from the NixOS generation file.
pub const GenerationInfo = struct {
    nixosVersion: ?[]const u8 = null,
    nixpkgsRevision: ?[]const u8 = null,
    configurationRevision: ?[]const u8 = null,
};

pub fn generationMain(allocator: Allocator, args: GenerationArgs) u8 {
    if (!fileExistsAbsolute(Constants.etc_nixos)) {
        log.err("the generation command is unsupported on non-NixOS systems", .{});
        return 3;
    }

    return switch (args.subcommand.?) {
        .diff => |sub_args| generationDiff.generationDiffMain(allocator, sub_args, args.profile),
        .list => |sub_args| generationList.generationListMain(allocator, args.profile, sub_args),
        .rollback => |sub_args| generationRollback.generationRollbackMain(allocator, sub_args, args.profile),
        .@"switch" => |sub_args| generationSwitch.generationSwitchMain(allocator, sub_args, args.profile),
    };
}

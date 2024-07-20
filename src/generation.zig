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

pub const GenerationCommand = struct {
    profile: ?[]const u8 = null,
    subcommand: ?GenerationSubcommand = null,

    const GenerationSubcommand = union(enum) {
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

    pub fn parseArgs(argv: *ArgIterator, parsed: *GenerationCommand) !?[]const u8 {
        var next_arg: ?[]const u8 = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--profile", "-p")) {
                parsed.profile = (try argparse.getNextArgs(argv, arg, 1))[0];
            } else if (argparse.isFlag(arg)) {
                return arg;
            } else if (parsed.subcommand == null) {
                if (mem.eql(u8, arg, "diff")) {
                    parsed.subcommand = .{ .diff = GenerationDiffArgs{} };
                } else if (mem.eql(u8, arg, "list")) {
                    parsed.subcommand = .{ .list = GenerationListArgs{} };
                } else if (mem.eql(u8, arg, "rollback")) {
                    parsed.subcommand = .{ .rollback = GenerationRollbackArgs{} };
                } else if (mem.eql(u8, arg, "switch")) {
                    parsed.subcommand = .{ .@"switch" = GenerationSwitchArgs{} };
                } else {
                    return arg;
                }
            }

            if (parsed.subcommand != null) {
                next_arg = switch (parsed.subcommand.?) {
                    .diff => |*sub_args| try GenerationDiffArgs.parseArgs(argv, sub_args),
                    .list => |*sub_args| try GenerationListArgs.parseArgs(argv, sub_args),
                    .rollback => |*sub_args| try GenerationRollbackArgs.parseArgs(argv, sub_args),
                    .@"switch" => |*sub_args| try GenerationSwitchArgs.parseArgs(argv, sub_args),
                };
            } else {
                next_arg = argv.next();
            }
        }

        if (parsed.subcommand == null) {
            argError("no subcommand specified", .{});
            return ArgParseError.MissingRequiredArgument;
        }

        return switch (parsed.subcommand.?) {
            .diff => |*sub_args| try GenerationDiffArgs.parseArgs(argv, sub_args),
            .list => |*sub_args| try GenerationListArgs.parseArgs(argv, sub_args),
            .rollback => |*sub_args| try GenerationRollbackArgs.parseArgs(argv, sub_args),
            .@"switch" => |*sub_args| try GenerationSwitchArgs.parseArgs(argv, sub_args),
        };
    }
};

pub fn generationMain(allocator: Allocator, args: GenerationCommand) u8 {
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

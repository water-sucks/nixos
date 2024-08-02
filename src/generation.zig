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

const generationDelete = @import("generation/delete.zig");
const generationDiff = @import("generation/diff.zig");
const generationList = @import("generation/list.zig");
const generationRollback = @import("generation/rollback.zig");
const generationSwitch = @import("generation/switch.zig");
const GenerationDeleteCommand = generationDelete.GenerationDeleteCommand;
const GenerationDiffCommand = generationDiff.GenerationDiffCommand;
const GenerationListCommand = generationList.GenerationListCommand;
const GenerationSwitchCommand = generationSwitch.GenerationSwitchCommand;
const GenerationRollbackCommand = generationRollback.GenerationRollbackCommand;

const GenerationError = error{};

pub const GenerationCommand = struct {
    profile: ?[]const u8 = null,
    subcommand: ?GenerationSubcommand = null,

    const Self = @This();

    const GenerationSubcommand = union(enum) {
        delete: GenerationDeleteCommand,
        diff: GenerationDiffCommand,
        list: GenerationListCommand,
        rollback: GenerationRollbackCommand,
        @"switch": GenerationSwitchCommand,
    };

    pub const usage =
        \\Manage NixOS generations on this machine.
        \\
        \\Usage:
        \\    nixos generation [options] <COMMAND>
        \\
        \\Commands:
        \\    delete              Delete generation(s) from this system
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

    pub fn parseArgs(allocator: Allocator, argv: *ArgIterator, parsed: *GenerationCommand) !?[]const u8 {
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
                if (mem.eql(u8, arg, "delete")) {
                    parsed.subcommand = .{ .delete = GenerationDeleteCommand.init(allocator) };
                } else if (mem.eql(u8, arg, "diff")) {
                    parsed.subcommand = .{ .diff = GenerationDiffCommand{} };
                } else if (mem.eql(u8, arg, "list")) {
                    parsed.subcommand = .{ .list = GenerationListCommand{} };
                } else if (mem.eql(u8, arg, "rollback")) {
                    parsed.subcommand = .{ .rollback = GenerationRollbackCommand{} };
                } else if (mem.eql(u8, arg, "switch")) {
                    parsed.subcommand = .{ .@"switch" = GenerationSwitchCommand{} };
                } else {
                    return arg;
                }
            }

            if (parsed.subcommand != null) {
                next_arg = switch (parsed.subcommand.?) {
                    .delete => |*sub_args| try GenerationDeleteCommand.parseArgs(argv, sub_args),
                    .diff => |*sub_args| try GenerationDiffCommand.parseArgs(argv, sub_args),
                    .list => |*sub_args| try GenerationListCommand.parseArgs(argv, sub_args),
                    .rollback => |*sub_args| try GenerationRollbackCommand.parseArgs(argv, sub_args),
                    .@"switch" => |*sub_args| try GenerationSwitchCommand.parseArgs(argv, sub_args),
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
            .delete => |*sub_args| try GenerationDeleteCommand.parseArgs(argv, sub_args),
            .diff => |*sub_args| try GenerationDiffCommand.parseArgs(argv, sub_args),
            .list => |*sub_args| try GenerationListCommand.parseArgs(argv, sub_args),
            .rollback => |*sub_args| try GenerationRollbackCommand.parseArgs(argv, sub_args),
            .@"switch" => |*sub_args| try GenerationSwitchCommand.parseArgs(argv, sub_args),
        };
    }

    pub fn deinit(self: Self) void {
        switch (self.subcommand.?) {
            .delete => |args| args.deinit(),
            else => {},
        }
    }
};

pub fn generationMain(allocator: Allocator, args: GenerationCommand) u8 {
    if (!fileExistsAbsolute(Constants.etc_nixos)) {
        log.err("the generation command is unsupported on non-NixOS systems", .{});
        return 3;
    }

    return switch (args.subcommand.?) {
        .delete => |_| 0,
        .diff => |sub_args| generationDiff.generationDiffMain(allocator, sub_args, args.profile),
        .list => |sub_args| generationList.generationListMain(allocator, args.profile, sub_args),
        .rollback => |sub_args| generationRollback.generationRollbackMain(allocator, sub_args, args.profile),
        .@"switch" => |sub_args| generationSwitch.generationSwitchMain(allocator, sub_args, args.profile),
    };
}

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

const generationList = @import("generation/list.zig");
const generationRollback = @import("generation/rollback.zig");
const generationSwitch = @import("generation/switch.zig");
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
        list: GenerationListArgs,
        rollback: GenerationRollbackArgs,
        @"switch": GenerationSwitchArgs,
    };

    pub const usage =
        \\Manage NixOS generations on this machine.
        \\
        \\Usage:
        \\    nixos generation [options] <command>
        \\
        \\Commands:
        \\    list              List all NixOS generations in current profile
        \\    rollback          Activate the previous generation
        \\    switch <NUMBER>   Activate the generation with the given number
        \\
        \\Options:
        \\    -h, --help        Show this help menu
        \\    -p, --profile     System profile to use
        \\
        \\For more information about a subcommand, add --help after.
        \\
    ;

    inline fn getSwitchArg(argv: *ArgIterator) !usize {
        const arg = argv.next();
        if (arg == null) {
            argError("missing required argument <NUMBER>", .{});
            return ArgParseError.MissingRequiredArgument;
        }

        const gen_number = std.fmt.parseInt(usize, arg.?, 10) catch |err| {
            switch (err) {
                error.InvalidCharacter => argError("'{s}' is not a number", .{arg.?}),
                error.Overflow => argError("unable to parse number '{s}'", .{arg.?}),
            }
            return ArgParseError.InvalidArgument;
        };

        return gen_number;
    }

    pub fn parseArgs(argv: *ArgIterator) !GenerationArgs {
        var result: GenerationArgs = GenerationArgs{};

        var next_arg: ?[]const u8 = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--profile", "-p")) {
                result.profile = (try argparse.getNextArgs(argv, arg, 1))[0];
            } else if (mem.eql(u8, arg, "list")) {
                result.subcommand = .{ .list = try GenerationListArgs.parseArgs(argv) };
            } else if (mem.eql(u8, arg, "rollback")) {
                result.subcommand = .{ .rollback = try GenerationRollbackArgs.parseArgs(argv) };
            } else if (mem.eql(u8, arg, "switch")) {
                result.subcommand = .{ .@"switch" = try GenerationSwitchArgs.parseArgs(argv) };
            } else {
                if (argparse.isFlag(arg)) {
                    argError("unrecognised flag '{s}'", .{arg});
                } else {
                    if (result.subcommand == null) {
                        argError("unknown subcommand '{s}'", .{arg});
                        return ArgParseError.InvalidSubcommand;
                    }
                    argError("argument '{s}' is not valid in this context", .{arg});
                }
                return ArgParseError.InvalidArgument;
            }

            next_arg = argv.next();
        }

        if (result.subcommand == null) {
            argError("no subcommand specified", .{});
            return ArgParseError.MissingRequiredArgument;
        }

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
        .list => |sub_args| generationList.generationListMain(allocator, args.profile, sub_args),
        .rollback => |sub_args| generationRollback.generationRollbackMain(allocator, sub_args, args.profile),
        .@"switch" => |sub_args| generationSwitch.generationSwitchMain(allocator, sub_args, args.profile),
    };
}

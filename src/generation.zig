const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argIs = argparse.argIs;
const isFlag = argparse.isFlag;
const argError = argparse.argError;

const log = @import("log.zig");

const utils = @import("utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;

const generationList = @import("generation/list.zig");
const generationRollback = @import("generation/rollback.zig");
const generationSwitch = @import("generation/switch.zig");
const GenerationListArgs = generationList.GenerationListArgs;

const GenerationError = error{};

pub const GenerationArgs = struct {
    // System profile directory to use
    profile: ?[]const u8 = null,
    // Subcommand that will be ran
    subcommand: ?GenerationCommand = null,

    const GenerationCommand = union(enum) {
        list: GenerationListArgs,
        rollback,
        @"switch": usize,
    };

    pub const usage =
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
        \\        --profile     System profile to use
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
                result.subcommand = .rollback;
                return result;
            } else if (mem.eql(u8, arg, "switch")) {
                result.subcommand = .{ .@"switch" = try getSwitchArg(argv) };
            } else {
                if (argparse.isFlag(arg)) {
                    argError("unrecognised flag '{s}'", .{arg});
                } else {
                    if (result.subcommand == null) {
                        argError("unknown subcommand '{s}'", .{arg});
                        return ArgParseError.InvalidSubcommand;
                    } else {
                        argError("argument '{s}' is not valid in this context", .{arg});
                    }
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

pub fn generationMain(allocator: Allocator, args: GenerationArgs) u8 {
    if (!fileExistsAbsolute("/etc/NIXOS")) {
        log.err("the build command is currently unsupported on non-NixOS systems", .{});
        return 3;
    }

    return switch (args.subcommand.?) {
        .list => |sub_args| generationList.generationListMain(allocator, args.profile, sub_args),
        .rollback => generationRollback.generationRollbackMain(allocator, args.profile),
        .@"switch" => |gen_number| generationSwitch.generationSwitchMain(allocator, gen_number, args.profile),
    };
}

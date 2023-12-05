const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArgIterator = std.process.ArgIterator;

const build = @import("build.zig");
const enter = @import("enter.zig");
const generation = @import("generation.zig");
const init = @import("init.zig");

const BuildArgs = build.BuildArgs;
const EnterArgs = enter.EnterArgs;
const GenerationArgs = generation.GenerationArgs;
const InitConfigArgs = init.InitConfigArgs;

const log = @import("log.zig");

const argparse = @import("argparse.zig");
const argError = argparse.argError;
const App = argparse.App;
const ArgParseError = argparse.ArgParseError;
const Command = argparse.Command;

const MainArgs = struct {
    subcommand: Subcommand = undefined,

    const Subcommand = union(enum) {
        build: BuildArgs,
        enter: EnterArgs,
        init: InitConfigArgs,
        generation: GenerationArgs,
    };

    const usage =
        \\A tool for managing NixOS installations.
        \\
        \\Usage:
        \\    nixos <command> [command options]
        \\
        \\Commands:
        \\    build              Build a NixOS configuration
        \\    enter              Chroot into a NixOS installation
        \\    generation         Manage NixOS generations
        \\    init               Initialize a configuration.nix file
        \\
        \\Options:
        \\    -h, --help    Show this help menu
        \\
        \\For more information about a command, add --help after.
        \\
    ;

    pub fn parseArgs(allocator: Allocator, argv: *ArgIterator) !MainArgs {
        var result: MainArgs = MainArgs{};

        const next_arg = argv.next();

        if (next_arg == null) {
            argError("no subcommand specified", .{});
            return ArgParseError.MissingRequiredArgument;
        }

        const arg = next_arg.?;

        if (argparse.argIs(arg, "--help", "-h")) {
            log.print(usage, .{});
            return ArgParseError.HelpInvoked;
        }

        if (mem.eql(u8, arg, "build")) {
            result.subcommand = .{ .build = try BuildArgs.parseArgs(allocator, argv) };
        } else if (mem.eql(u8, arg, "enter")) {
            result.subcommand = .{ .enter = try EnterArgs.parseArgs(allocator, argv) };
        } else if (mem.eql(u8, arg, "generation")) {
            result.subcommand = .{ .generation = try GenerationArgs.parseArgs(argv) };
        } else if (mem.eql(u8, arg, "init")) {
            result.subcommand = .{ .init = try InitConfigArgs.parseArgs(argv) };
        } else {
            if (argparse.isFlag(arg)) {
                argError("unrecognised flag '{s}'", .{arg});
                return ArgParseError.InvalidArgument;
            } else {
                argError("unknown subcommand '{s}'", .{arg});
                return ArgParseError.InvalidSubcommand;
            }
        }

        return result;
    }
};

pub fn main() !u8 {
    // If you want to be decent about memory management, use this.
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer {
    //     const result = gpa.deinit();
    //     std.debug.print("alloc result: {}\n", .{result});
    // }
    // const allocator = gpa.allocator();

    // If you're lazy when it comes to memory management, use this.
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const allocator = arena_allocator.allocator();

    var argv = try std.process.argsWithAllocator(allocator);
    defer argv.deinit();

    // Skip executable name
    _ = argv.next();

    const structured_args = MainArgs.parseArgs(allocator, &argv) catch |err| {
        switch (err) {
            ArgParseError.HelpInvoked => return 0,
            else => return 2,
        }
    };

    const status = switch (structured_args.subcommand) {
        .build => |args| build.buildMain(allocator, args),
        .enter => |args| enter.enterMain(allocator, args),
        .generation => |args| generation.generationMain(allocator, args),
        .init => |args| init.initConfigMain(allocator, args),
    };

    return status;
}

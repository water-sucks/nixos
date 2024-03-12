const std = @import("std");
const opts = @import("options");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArgIterator = std.process.ArgIterator;

const apply = @import("apply.zig");
const enter = @import("enter.zig");
const features = @import("features.zig");
const generation = @import("generation.zig");
const info = @import("info.zig");
const init = @import("init.zig");
const install = @import("install.zig");
const manual = @import("manual.zig");

const ApplyArgs = apply.ApplyArgs;
const EnterArgs = enter.EnterArgs;
const GenerationArgs = generation.GenerationArgs;
const InfoArgs = info.InfoArgs;
const InitConfigArgs = init.InitConfigArgs;
const InstallArgs = install.InstallArgs;

const config = @import("config.zig");

const log = @import("log.zig");

const argparse = @import("argparse.zig");
const argError = argparse.argError;
const App = argparse.App;
const ArgParseError = argparse.ArgParseError;
const Command = argparse.Command;

const nix = @import("nix");

const MainArgs = struct {
    subcommand: Subcommand = undefined,

    const Subcommand = union(enum) {
        apply: ApplyArgs,
        enter: EnterArgs,
        generation: GenerationArgs,
        features,
        info: InfoArgs,
        init: InitConfigArgs,
        install: InstallArgs,
        manual,
    };

    const usage =
        \\A tool for managing NixOS installations.
        \\
        \\Usage:
        \\    nixos <COMMAND>
        \\
        \\Commands:
        \\    apply         Build/activate a NixOS configuration
        \\    enter         Chroot into a NixOS installation
        \\    generation    Manage NixOS generations
        \\    info          Show info about the currently running generation
        \\    init          Initialize a configuration.nix file
        \\    install       Install a NixOS configuration and bootloader
        \\    manual        Open the NixOS manual in a browser
        \\
        \\Options:
        \\    -h, --help       Show this help menu
        \\    -v, --version    Print version information
        \\
        \\For more information about a command and its options, add --help after.
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
        } else if (argparse.argIs(arg, "--version", "-v")) {
            return ArgParseError.VersionInvoked;
        }

        if (mem.eql(u8, arg, "apply")) {
            result.subcommand = .{ .apply = try ApplyArgs.parseArgs(allocator, argv) };
        } else if (mem.eql(u8, arg, "enter")) {
            result.subcommand = .{ .enter = try EnterArgs.parseArgs(allocator, argv) };
        } else if (mem.eql(u8, arg, "features")) {
            result.subcommand = .features;
        } else if (mem.eql(u8, arg, "generation")) {
            result.subcommand = .{ .generation = try GenerationArgs.parseArgs(argv) };
        } else if (mem.eql(u8, arg, "info")) {
            result.subcommand = .{ .info = try InfoArgs.parseArgs(argv) };
        } else if (mem.eql(u8, arg, "init")) {
            result.subcommand = .{ .init = try InitConfigArgs.parseArgs(argv) };
        } else if (mem.eql(u8, arg, "install")) {
            result.subcommand = .{ .install = try InstallArgs.parseArgs(allocator, argv) };
        } else if (mem.eql(u8, arg, "manual")) {
            result.subcommand = .manual;
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

    config.parseConfig(allocator) catch |err| {
        log.err("error parsing settings: {s}", .{@errorName(err)});
        return 2;
    };
    defer config.deinit();

    const nix_context = nix.util.NixContext.init() catch {
        log.err("out of memory, cannot continue", .{});
        return 1;
    };
    defer nix_context.deinit();

    nix.util.init(nix_context) catch unreachable;
    nix.store.init(nix_context) catch unreachable;
    nix.expr.init(nix_context) catch unreachable;

    var argv = try std.process.argsWithAllocator(allocator);
    defer argv.deinit();

    // Skip executable name
    _ = argv.next();

    const structured_args = MainArgs.parseArgs(allocator, &argv) catch |err| {
        switch (err) {
            ArgParseError.HelpInvoked => return 0,
            ArgParseError.VersionInvoked => {
                const stdout = std.io.getStdOut().writer();
                stdout.print(opts.version ++ "\n", .{}) catch unreachable;
                return 0;
            },
            else => return 2,
        }
    };

    const status = switch (structured_args.subcommand) {
        .apply => |args| apply.applyMain(allocator, args),
        .enter => |args| enter.enterMain(allocator, args),
        .features => {
            features.printFeatures();
            return 0;
        },
        .generation => |args| generation.generationMain(allocator, args),
        .info => |args| info.infoMain(allocator, args),
        .init => |args| init.initConfigMain(allocator, args),
        .install => |args| install.installMain(allocator, args),
        .manual => return manual.manualMain(allocator),
    };

    return status;
}

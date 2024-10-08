const std = @import("std");
const opts = @import("options");
const io = std.io;
const mem = std.mem;
const process = std.process;
const posix = std.posix;
const Allocator = mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const ArrayList = std.ArrayList;

const alias = @import("alias.zig");
const apply = @import("apply.zig");
const enter = @import("enter.zig");
const features = @import("features.zig");
const generation = @import("generation.zig");
const info = @import("info.zig");
const init = @import("init.zig");
const install = @import("install.zig");
const manual = @import("manual.zig");
const option = @import("option.zig");
const repl = @import("repl.zig");

const AliasesCommand = alias.AliasesCommand;
const ApplyCommand = apply.ApplyCommand;
const EnterCommand = enter.EnterCommand;
const FeaturesCommand = features.FeaturesCommand;
const GenerationCommand = generation.GenerationCommand;
const InfoCommand = info.InfoCommand;
const InitConfigCommand = init.InitConfigCommand;
const InstallCommand = install.InstallCommand;
const ReplCommand = repl.ReplCommand;
const OptionCommand = option.OptionCommand;

const config = @import("config.zig");

const log = @import("log.zig");

const argparse = @import("argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argError = argparse.argError;
const argIs = argparse.argIs;
const getNextArgs = argparse.getNextArgs;

const Constants = @import("constants.zig");

// const nix = @import("nix");

const utils = @import("utils.zig");
const println = utils.println;

const MainArgs = struct {
    allocator: Allocator,
    config_values: ArrayList([]const u8),
    color_always: bool = false,
    subcommand: ?Subcommand = null,

    const Self = @This();

    const Subcommand = union(enum) {
        aliases: AliasesCommand,
        alias: []const []const u8,
        apply: ApplyCommand,
        enter: EnterCommand,
        features: FeaturesCommand,
        generation: GenerationCommand,
        info: InfoCommand,
        init: InitConfigCommand,
        install: InstallCommand,
        manual,
        option: OptionCommand,
        repl: ReplCommand,
    };

    const usage =
        \\A tool for managing NixOS installations.
        \\
        \\Usage:
        \\    nixos <COMMAND>
        \\
        \\Commands:
        \\    aliases       List configured aliases
        \\    apply         Build/activate a NixOS configuration
        \\    enter         Chroot into a NixOS installation
        \\    features      Show information about features for debugging
        \\    generation    Manage NixOS generations
        \\    info          Show info about the currently running generation
        \\    init          Initialize a configuration.nix file
        \\    install       Install a NixOS configuration and bootloader
        \\    manual        Open the NixOS manual in a browser
        \\    option        Query NixOS options and their details
        \\    repl          Start a Nix REPL with system configuration loaded
        \\
        \\Options:
        \\    -c, --config <KEY>=<VALUE>    Set a configuration value
        \\    -C, --color-always            Always color output when possible
        \\    -h, --help                    Show this help menu
        \\    -v, --version                 Print version information
        \\
        \\For more information about a command and its options, add --help after.
        \\
    ;

    pub fn parseArgs(allocator: Allocator, argv: *ArgIterator) !MainArgs {
        var result: MainArgs = MainArgs{
            .allocator = allocator,
            .config_values = ArrayList([]const u8).init(allocator),
        };
        errdefer result.deinit();

        const c = config.getConfig();

        var next_arg: ?[]const u8 = argv.next();
        while (next_arg) |arg| {
            if (argparse.argIs(arg, "--config", "-c")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                try result.config_values.append(next);
            } else if (argparse.argIs(arg, "--color-always", "-C")) {
                result.color_always = true;
            } else if (argparse.argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argparse.argIs(arg, "--version", "-v")) {
                return ArgParseError.VersionInvoked;
            } else if (argparse.isFlag(arg)) {
                argError("unrecognised flag '{s}'", .{arg});
                return ArgParseError.InvalidArgument;
            } else if (result.subcommand == null) {
                if (mem.eql(u8, arg, "aliases")) {
                    result.subcommand = .{ .aliases = AliasesCommand{} };
                } else if (mem.eql(u8, arg, "apply")) {
                    result.subcommand = .{ .apply = ApplyCommand.init(allocator) };
                } else if (mem.eql(u8, arg, "enter")) {
                    result.subcommand = .{ .enter = EnterCommand.init(allocator) };
                } else if (mem.eql(u8, arg, "features")) {
                    result.subcommand = .{ .features = FeaturesCommand{} };
                } else if (mem.eql(u8, arg, "generation")) {
                    result.subcommand = .{ .generation = GenerationCommand{} };
                } else if (mem.eql(u8, arg, "info")) {
                    result.subcommand = .{ .info = InfoCommand{} };
                } else if (mem.eql(u8, arg, "init")) {
                    result.subcommand = .{ .init = InitConfigCommand{} };
                } else if (mem.eql(u8, arg, "install")) {
                    result.subcommand = .{ .install = InstallCommand.init(allocator) };
                } else if (mem.eql(u8, arg, "manual")) {
                    result.subcommand = .manual;
                } else if (mem.eql(u8, arg, "option")) {
                    result.subcommand = .{ .option = OptionCommand.init(allocator) };
                } else if (mem.eql(u8, arg, "repl")) {
                    result.subcommand = .{ .repl = ReplCommand.init(allocator) };
                } else {
                    const is_alias = blk: {
                        if (c.aliases) |aliases| {
                            var it = aliases.iterator();
                            while (it.next()) |kv| {
                                const key = kv.key_ptr.*;
                                const value = kv.value_ptr.array.items;

                                if (mem.eql(u8, arg, key)) {
                                    const resolved_alias_args = try allocator.alloc([]const u8, value.len);
                                    errdefer allocator.free(resolved_alias_args);
                                    for (value, 0..) |a, i| {
                                        resolved_alias_args[i] = a.string;
                                    }
                                    result.subcommand = .{ .alias = resolved_alias_args };
                                    break :blk true;
                                }
                            }
                        }
                        break :blk false;
                    };

                    if (is_alias) {
                        return result;
                    } else {
                        argError("unknown subcommand '{s}'", .{arg});
                        return ArgParseError.InvalidSubcommand;
                    }
                }
            } else {
                argError("argument '{s}' is not valid in this context", .{arg});
                return ArgParseError.InvalidSubcommand;
            }

            if (result.subcommand != null) {
                next_arg = switch (result.subcommand.?) {
                    .aliases => |*sub_args| try AliasesCommand.parseArgs(argv, sub_args),
                    .alias => unreachable,
                    .apply => |*sub_args| try ApplyCommand.parseArgs(argv, sub_args),
                    .enter => |*sub_args| try EnterCommand.parseArgs(argv, sub_args),
                    .features => |*sub_args| try FeaturesCommand.parseArgs(argv, sub_args),
                    .generation => |*sub_args| try GenerationCommand.parseArgs(allocator, argv, sub_args),
                    .info => |*sub_args| try InfoCommand.parseArgs(argv, sub_args),
                    .init => |*sub_args| try InitConfigCommand.parseArgs(argv, sub_args),
                    .install => |*sub_args| try InstallCommand.parseArgs(argv, sub_args),
                    .manual => null,
                    .option => |*sub_args| try OptionCommand.parseArgs(argv, sub_args),
                    .repl => |*sub_args| try ReplCommand.parseArgs(argv, sub_args),
                };
            } else {
                next_arg = argv.next();
            }
        }

        if (result.subcommand == null) {
            argError("no subcommand specified", .{});
            return ArgParseError.MissingRequiredArgument;
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.config_values.deinit();

        if (self.subcommand != null) {
            switch (self.subcommand.?) {
                .alias => |args| self.allocator.free(args),
                .apply => |*args| args.deinit(),
                .enter => |*args| args.deinit(),
                .install => |*args| args.deinit(),
                .repl => |*args| args.deinit(),
                .option => |*args| args.deinit(),
                else => {},
            }
        }
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

    config.parseConfig(allocator) catch {};
    defer config.deinit();

    // This initially sets NO_COLOR to a reasonable value before the configuration
    // and arguments are parsed. This will be re-set later.
    const no_color_is_set = mem.eql(u8, posix.getenv("NO_COLOR") orelse "", "1");
    Constants.use_color = !no_color_is_set and
        io.getStdOut().supportsAnsiEscapeCodes() and
        io.getStdErr().supportsAnsiEscapeCodes();

    // const nix_context = nix.util.NixContext.init() catch {
    //     log.err("out of memory, cannot continue", .{});
    //     return 1;
    // };
    // defer nix_context.deinit();
    //
    // nix.util.init(nix_context) catch unreachable;
    // nix.store.init(nix_context) catch unreachable;
    // nix.expr.init(nix_context) catch unreachable;

    var argv = try std.process.argsWithAllocator(allocator);
    defer argv.deinit();

    // Skip executable name
    _ = argv.next();

    var structured_args = MainArgs.parseArgs(allocator, &argv) catch |err| {
        switch (err) {
            ArgParseError.HelpInvoked => return 0,
            ArgParseError.VersionInvoked => {
                const stdout = io.getStdOut().writer();
                stdout.print(opts.version ++ "\n", .{}) catch unreachable;
                return 0;
            },
            else => return 2,
        }
    };
    defer structured_args.deinit();

    for (structured_args.config_values.items) |pair| {
        config.setConfigValue(pair) catch return 2;
    }
    config.validateConfig(allocator) catch return 2;

    const c = config.getConfig();

    // Now that we have the real color settings from parsing
    // the configuration and command-line arguments, set it.
    //
    // Precedence of color settings:
    // 1. -C flag -> true
    // 2. NO_COLOR=1 -> false
    // 3. `color` setting from config (default: true)
    if (structured_args.color_always) {
        Constants.use_color = true;
    } else if (no_color_is_set) {
        Constants.use_color = false;
    } else {
        Constants.use_color = c.color and io.getStdOut().supportsAnsiEscapeCodes() and
            io.getStdErr().supportsAnsiEscapeCodes();
    }

    const status = switch (structured_args.subcommand.?) {
        .aliases => |args| {
            alias.printAliases(args);
            return 0;
        },
        .alias => |resolved| {
            defer allocator.free(resolved);
            execAlias(allocator, resolved) catch |err| {
                log.err("error executing alias command: {s}", .{@errorName(err)});
                return 1;
            };
            return 0;
        },
        .apply => |args| apply.applyMain(allocator, args),
        .enter => |args| enter.enterMain(allocator, args),
        .features => |args| {
            features.printFeatures(args);
            return 0;
        },
        .generation => |args| generation.generationMain(allocator, args),
        .info => |args| info.infoMain(allocator, args),
        .init => |args| init.initConfigMain(allocator, args),
        .install => |args| install.installMain(allocator, args),
        .manual => manual.manualMain(allocator),
        .option => |args| option.optionMain(allocator, args),
        .repl => |args| repl.replMain(allocator, args),
    };

    return status;
}

fn execAlias(allocator: Allocator, resolved: []const []const u8) !void {
    const original_args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, original_args);

    var new_args = ArrayList([]const u8).init(allocator);
    defer new_args.deinit();

    try new_args.append(original_args[0]);
    try new_args.appendSlice(resolved);
    if (original_args.len > 2) {
        try new_args.appendSlice(original_args[2..]);
    }

    return process.execve(allocator, new_args.items, null);
}

const std = @import("std");
const opts = @import("options");
const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const json = std.json;
const mem = std.mem;
const posix = std.posix;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argIs = argparse.argIs;
const argError = argparse.argError;
const getNextArgs = argparse.getNextArgs;

const Constants = @import("constants.zig");

const log = @import("log.zig");

const utils = @import("utils.zig");
const FlakeRef = utils.FlakeRef;
const fileExistsAbsolute = utils.fileExistsAbsolute;
const runCmd = utils.runCmd;
const println = utils.println;
const search = utils.search;

pub const OptionError = error{
    NoOptionCache,
    NoResultFound,
    UnsupportedOs,
};

pub const OptionCommand = struct {
    option: ?[]const u8 = null,
    json: bool = false,
    interactive: bool = false,
    includes: ArrayList([]const u8),

    const Self = @This();

    const usage =
        \\Query available NixOS module options for this system.
        \\
        \\Usage:
        \\    nixos option [NAME] [options]
        \\
        \\Arguments:
        \\    [NAME]    Name of option to use. Not required in interactive mode.
        \\
        \\Options:
        \\    -h, --help              Show this help menu
        \\    -i, --interactive       Show interactive search bar for options
        \\    -I, --include <PATH>    Add a path value to the Nix search path
        \\    -j, --json              Output option information in JSON format
        \\
    ;

    pub fn init(allocator: Allocator) Self {
        return OptionCommand{
            .includes = ArrayList([]const u8).init(allocator),
        };
    }

    pub fn parseArgs(argv: *ArgIterator, parsed: *OptionCommand) !?[]const u8 {
        var next_arg = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--interactive", "-i")) {
                parsed.interactive = true;
            } else if (argIs(arg, "--include", "-I")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                try parsed.includes.append(next);
            } else if (argIs(arg, "--json", "-j")) {
                parsed.json = true;
            } else {
                if (parsed.option == null) {
                    parsed.option = arg;
                } else {
                    return arg;
                }
            }

            next_arg = argv.next();
        }

        if (parsed.interactive and parsed.json) {
            argError("--interactive and --json flags conflict", .{});
            return ArgParseError.ConflictingOptions;
        }

        if (!parsed.interactive and parsed.option == null) {
            argError("missing required argument <NAME>", .{});
            return ArgParseError.MissingRequiredArgument;
        }

        return null;
    }

    pub fn deinit(self: *Self) void {
        self.includes.deinit();
    }
};

const NixosOptionFromFile = struct {
    description: []const u8,
    type: []const u8,
    default: ?struct {
        _type: []const u8,
        text: []const u8,
    } = null,
    example: ?struct {
        _type: []const u8,
        text: []const u8,
    } = null,
    loc: []const []const u8,
    readOnly: bool,
    declarations: []const []const u8,
};

fn findNixosOptionFilepathLegacy(allocator: Allocator) ![]const u8 {
    const argv = &.{ "nix-build", "<nixpkgs/nixos>", "--no-out-link", "-A", "config.system.build.manual.optionsJSON" };

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
        .stderr_type = .Ignore,
    }) catch return OptionError.NoOptionCache;

    if (result.status != 0) {
        log.err("unable to find options cache; cannot continue", .{});
        return OptionError.NoOptionCache;
    }
    defer allocator.free(result.stdout.?);

    return try allocator.dupe(u8, result.stdout.?);
}

fn findNixosOptionFilepathFlake(allocator: Allocator) ![]const u8 {
    var hostname_buf: [posix.HOST_NAME_MAX]u8 = undefined;
    var flake_ref = utils.findFlakeRef() catch return OptionError.NoOptionCache;
    flake_ref.inferSystemNameIfNeeded(&hostname_buf) catch return OptionError.NoOptionCache;

    const option_attr = try fmt.allocPrint(allocator, "{s}#nixosConfigurations.{s}.config.system.build.manual.optionsJSON", .{
        flake_ref.uri,
        flake_ref.system,
    });
    defer allocator.free(option_attr);

    const argv = &.{ "nix", "build", "--no-link", "--print-out-paths", option_attr };

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
        .stderr_type = .Ignore,
    }) catch return OptionError.NoOptionCache;

    if (result.status != 0) {
        log.err("unable to find options cache; cannot continue", .{});
        return OptionError.NoOptionCache;
    }
    defer allocator.free(result.stdout.?);

    return try allocator.dupe(u8, result.stdout.?);
}

fn loadOptionsFromFile(allocator: Allocator, filename: []const u8) !json.Parsed(json.ArrayHashMap(NixosOptionFromFile)) {
    var file = fs.openFileAbsolute(filename, .{}) catch |err| {
        log.err("cannot open options cache file at {s}: {s}", .{ filename, @errorName(err) });
        return err;
    };
    defer file.close();

    var buffered_reader = io.bufferedReader(file.reader());

    var json_reader = std.json.reader(allocator, buffered_reader.reader());
    defer json_reader.deinit();

    const parsed = std.json.parseFromTokenSource(json.ArrayHashMap(NixosOptionFromFile), allocator, &json_reader, .{
        .ignore_unknown_fields = true,
        .duplicate_field_behavior = .use_last,
    }) catch |err| {
        log.err("unable to parse options cache file at {s}: {s}", .{ filename, @errorName(err) });
        return err;
    };

    return parsed;
}

const RESET = "\x1B[0m";
const BOLD = "\x1B[1m";
const ITALIC = "\x1B[3m";
const UNDERLINE = "\x1B[4m";

fn displayOption(name: []const u8, opt: NixosOptionFromFile) void {
    const stdout = io.getStdOut().writer();

    const default = if (opt.default) |d| d.text else null;

    println(stdout, BOLD ++ "Name\n" ++ RESET ++ "{s}\n", .{name});
    println(stdout, BOLD ++ "Description\n" ++ RESET ++ "{s}\n", .{opt.description});
    println(stdout, BOLD ++ "Type\n" ++ RESET ++ "{s}\n", .{opt.type});
    println(stdout, BOLD ++ "Default\n" ++ RESET ++ "{s}\n", .{default orelse "No default value."});
    if (opt.example) |example| {
        println(stdout, BOLD ++ "Example\n" ++ RESET ++ "{s}\n", .{example.text});
    }
    println(stdout, BOLD ++ "Declared In" ++ RESET, .{});
    for (opt.declarations) |decl| {
        println(stdout, ITALIC ++ "  - {s}" ++ RESET, .{decl});
    }
    if (opt.readOnly) {
        println(stdout, UNDERLINE ++ ITALIC ++ "\nThis option is read-only." ++ RESET, .{});
    }
}

fn option(allocator: Allocator, args: OptionCommand) !void {
    if (!fileExistsAbsolute(Constants.etc_nixos)) {
        log.err("the option command is unsupported on non-NixOS systems", .{});
        return OptionError.UnsupportedOs;
    }

    if (args.interactive) {
        log.info("this is currently unimplemented; coming soon!", .{});
        return;
    }

    const option_cache_realized_drv = if (opts.flake)
        try findNixosOptionFilepathFlake(allocator)
    else
        try findNixosOptionFilepathLegacy(allocator);
    defer allocator.free(option_cache_realized_drv);

    const options_filename = try fs.path.join(allocator, &.{ option_cache_realized_drv, "/share/doc/nixos/options.json" });
    defer allocator.free(options_filename);

    var parsed_options = loadOptionsFromFile(allocator, options_filename) catch return OptionError.NoOptionCache;
    defer parsed_options.deinit();

    const option_map = parsed_options.value.map;
    const option_input = args.option.?;

    var option_iter = option_map.iterator();

    const stdout = io.getStdOut().writer();

    while (option_iter.next()) |kv| {
        const key = kv.key_ptr.*;
        const value = kv.value_ptr.*;

        if (mem.eql(u8, option_input, key)) {
            if (args.json) {
                const output = .{
                    .name = key,
                    .description = value.description,
                    .type = value.type,
                    .default = if (value.default) |d| d.text else null,
                    .example = if (value.example) |e| e.text else null,
                    .declarations = value.declarations,
                    .readOnly = value.readOnly,
                };

                json.stringify(output, .{ .whitespace = .indent_2 }, stdout) catch unreachable;
            } else {
                displayOption(key, value);
            }
            return;
        }
    } else {
        const candidate_filter_buf = try allocator.alloc(search.Candidate, option_map.count());
        defer allocator.free(candidate_filter_buf);

        const similar_options = blk: {
            const raw_filtered = search.rankCandidates(candidate_filter_buf, option_map.keys(), &.{option_input}, false, true, true);
            if (raw_filtered.len < 10) {
                break :blk raw_filtered;
            }
            break :blk raw_filtered[0..10];
        };

        const error_message = try fmt.allocPrint(allocator, "no exact match for query '{s}' found", .{option_input});
        defer allocator.free(error_message);

        if (args.json) {
            const similar_options_str_list = try allocator.alloc([]const u8, similar_options.len);
            defer allocator.free(similar_options_str_list);

            for (similar_options, similar_options_str_list) |opt_name, *dst| {
                dst.* = opt_name.str;
            }

            const output = .{
                .message = error_message,
                .similar_options = similar_options_str_list,
            };

            json.stringify(output, .{ .whitespace = .indent_2 }, stdout) catch unreachable;
        } else {
            log.err("{s}", .{error_message});

            if (similar_options.len > 0) {
                log.print("\nSome similar options were found:\n", .{});
                for (similar_options) |c| {
                    log.print("  - {s}\n", .{c.str});
                }
            } else {
                log.print("Try refining your search query.\n", .{});
            }
        }

        return OptionError.NoResultFound;
    }
}

pub fn optionMain(allocator: Allocator, args: OptionCommand) u8 {
    option(allocator, args) catch |err| switch (err) {
        OptionError.UnsupportedOs => return 3,
        else => return 1,
    };

    return 0;
}

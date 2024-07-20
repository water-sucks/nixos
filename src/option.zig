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
const ansi = utils.ansi;

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

fn findNixosOptionFilepathLegacy(allocator: Allocator, includes: []const []const u8) ![]const u8 {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix-build", "<nixpkgs/nixos>", "--no-out-link", "-A", "config.system.build.manual.optionsJSON" });
    for (includes) |include| {
        try argv.appendSlice(&.{ "-I", include });
    }

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
        .stderr_type = .Ignore,
    }) catch return OptionError.NoOptionCache;

    if (result.status != 0) {
        log.err("unable to find options cache; cannot continue", .{});
        return OptionError.NoOptionCache;
    }
    defer allocator.free(result.stdout.?);

    return try allocator.dupe(u8, result.stdout.?);
}

fn findNixosOptionFilepathFlake(allocator: Allocator, includes: []const []const u8) ![]const u8 {
    var hostname_buf: [posix.HOST_NAME_MAX]u8 = undefined;
    var flake_ref = utils.findFlakeRef() catch return OptionError.NoOptionCache;
    flake_ref.inferSystemNameIfNeeded(&hostname_buf) catch return OptionError.NoOptionCache;

    const option_attr = try fmt.allocPrint(allocator, "{s}#nixosConfigurations.{s}.config.system.build.manual.optionsJSON", .{
        flake_ref.uri,
        flake_ref.system,
    });
    defer allocator.free(option_attr);

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix", "build", "--no-link", "--print-out-paths", option_attr });
    for (includes) |include| {
        try argv.appendSlice(&.{ "-I", include });
    }
    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
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

fn displayOption(name: []const u8, opt: NixosOptionFromFile) void {
    const stdout = io.getStdOut().writer();

    // Descriptions more often than not have lots of newlines and spaces,
    // especially trailing ones. This should be trimmed.
    const description = mem.trim(u8, opt.description, "\n ");
    const default = if (opt.default) |d| d.text else null;

    if (Constants.use_color) {
        println(stdout, ansi.BOLD ++ "Name\n" ++ ansi.RESET ++ "{s}\n", .{name});
    } else {
        println(stdout, "Name\n{s}\n", .{name});
    }

    if (Constants.use_color) {
        println(stdout, ansi.BOLD ++ "Description\n" ++ ansi.RESET ++ "{s}\n", .{description});
    } else {
        println(stdout, "Description\n{s}\n", .{description});
    }

    if (Constants.use_color) {
        println(stdout, ansi.BOLD ++ "Type\n" ++ ansi.RESET ++ "{s}\n", .{opt.type});
    } else {
        println(stdout, "Type\n{s}\n", .{opt.type});
    }

    if (Constants.use_color) {
        println(stdout, ansi.BOLD ++ "Default\n" ++ ansi.RESET ++ "{s}\n", .{default orelse "No default value."});
    } else {
        println(stdout, "Default\n{s}\n", .{default orelse "No default value."});
    }

    if (opt.example) |example| {
        if (Constants.use_color) {
            println(stdout, ansi.BOLD ++ "Example\n" ++ ansi.RESET ++ "{s}\n", .{example.text});
        } else {
            println(stdout, "Example\n{s}\n", .{example.text});
        }
    }

    if (Constants.use_color) {
        println(stdout, ansi.BOLD ++ "Declared In" ++ ansi.RESET, .{});
    } else {
        println(stdout, "Declared In", .{});
    }

    for (opt.declarations) |decl| {
        if (Constants.use_color) {
            println(stdout, ansi.ITALIC ++ "  - {s}" ++ ansi.RESET, .{decl});
        } else {
            println(stdout, "  - {s}", .{decl});
        }
    }
    if (opt.readOnly) {
        if (Constants.use_color) {
            println(stdout, ansi.RED ++ ansi.ITALIC ++ "\nThis option is read-only." ++ ansi.RESET, .{});
        } else {
            println(stdout, "\nThis option is read-only.", .{});
        }
    }
}

const prebuilt_options_cache_filename = Constants.current_system ++ "/sw/share/doc/nixos/options.json";

fn option(allocator: Allocator, args: OptionCommand) !void {
    if (!fileExistsAbsolute(Constants.etc_nixos)) {
        log.err("the option command is unsupported on non-NixOS systems", .{});
        return OptionError.UnsupportedOs;
    }

    if (args.interactive) {
        log.info("this is currently unimplemented; coming soon!", .{});
        return;
    }

    var options_filename_alloc = false;
    const options_filename = blk: {
        if (fileExistsAbsolute(prebuilt_options_cache_filename)) {
            break :blk prebuilt_options_cache_filename;
        }

        const option_cache_realized_drv = if (opts.flake)
            try findNixosOptionFilepathFlake(allocator, args.includes.items)
        else
            try findNixosOptionFilepathLegacy(allocator, args.includes.items);
        defer allocator.free(option_cache_realized_drv);

        options_filename_alloc = true;
        break :blk try fs.path.join(allocator, &.{ option_cache_realized_drv, "/share/doc/nixos/options.json" });
    };
    defer if (options_filename_alloc) allocator.free(options_filename);

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
                    .description = mem.trim(u8, value.description, "\n "),
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

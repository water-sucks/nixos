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

const optionSearchUI = @import("option/ui.zig").optionSearchUI;

pub const OptionError = error{
    NoOptionCache,
    NoResultFound,
    UnsupportedOs,
    ResourceAccessFailed,
};

pub const OptionCommand = struct {
    option: ?[]const u8 = null,
    json: bool = false,
    interactive: bool = false,
    includes: ArrayList([]const u8),
    no_cache: bool = false,

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
        \\    -n, --no-cache          Do not attempt to use cache
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
            } else if (argIs(arg, "--no-cache", "-n")) {
                parsed.no_cache = true;
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

pub const NixosOption = struct {
    name: []const u8,
    description: ?[]const u8 = null,
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

const flake_options_cache_expr =
    \\let
    \\  flake = builtins.getFlake "{s}";
    \\  system = flake.nixosConfigurations."{s}";
    \\  inherit (system) pkgs;
    \\  inherit (pkgs) lib;
    \\
    \\  optionsList' = lib.optionAttrSetToDocList system.options;
    \\  optionsList = builtins.filter (v: v.visible && !v.internal) optionsList';
    \\
    \\  jsonFormat = pkgs.formats.json {{}};
    \\in
    \\  jsonFormat.generate "options-cache.json" optionsList
;
const legacy_options_cache_expr =
    \\let
    \\  system = import <nixpkgs/nixos> {};
    \\  inherit (system) pkgs;
    \\  inherit (pkgs) lib;
    \\
    \\  optionsList' = lib.optionAttrSetToDocList system.options;
    \\  optionsList = builtins.filter (v: v.visible && !v.internal) optionsList';
    \\
    \\  jsonFormat = pkgs.formats.json {};
    \\in
    \\  jsonFormat.generate "options-cache.json" optionsList
;

fn findNixosOptionFilepath(allocator: Allocator, includes: []const []const u8) ![]const u8 {
    var hostname_buf: [posix.HOST_NAME_MAX]u8 = undefined;

    const option_cache_expr: []const u8 = blk: {
        if (opts.flake) {
            var flake_ref = utils.findFlakeRef() catch return OptionError.NoOptionCache;
            flake_ref.inferSystemNameIfNeeded(&hostname_buf) catch return OptionError.NoOptionCache;
            break :blk try fmt.allocPrint(allocator, flake_options_cache_expr, .{
                flake_ref.uri,
                flake_ref.system,
            });
        }
        break :blk try allocator.dupe(u8, legacy_options_cache_expr);
    };
    defer allocator.free(option_cache_expr);

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix-build", "--no-out-link", "--expr", option_cache_expr });
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

fn loadOptionsFromFile(allocator: Allocator, filename: []const u8) !json.Parsed([]NixosOption) {
    var file = fs.openFileAbsolute(filename, .{}) catch |err| {
        log.err("cannot open options cache file at {s}: {s}", .{ filename, @errorName(err) });
        return err;
    };
    defer file.close();

    var buffered_reader = io.bufferedReader(file.reader());

    var json_reader = std.json.reader(allocator, buffered_reader.reader());
    defer json_reader.deinit();

    const parsed = std.json.parseFromTokenSource([]NixosOption, allocator, &json_reader, .{
        .ignore_unknown_fields = true,
        .duplicate_field_behavior = .use_last,
    }) catch |err| {
        log.err("unable to parse options cache file at {s}: {s}", .{ filename, @errorName(err) });
        return err;
    };

    return parsed;
}

fn displayOption(name: []const u8, opt: NixosOption) void {
    const stdout = io.getStdOut().writer();

    // A lot of attributes have lots of newlines and spaces,
    // especially trailing ones. This should be trimmed.
    const description = blk: {
        if (opt.description) |d| {
            break :blk mem.trim(u8, d, "\n ");
        }

        break :blk if (Constants.use_color)
            ansi.ITALIC ++ "(none)" ++ ansi.RESET
        else
            "(none)";
    };
    const default = blk: {
        if (opt.default) |d| {
            break :blk mem.trim(u8, d.text, "\n ");
        }
        break :blk if (Constants.use_color)
            ansi.ITALIC ++ "(none)" ++ ansi.RESET
        else
            "(none)";
    };
    const example = if (opt.example) |e| mem.trim(u8, e.text, "\n ") else null;

    if (Constants.use_color) {
        println(stdout, ansi.BOLD ++ "Name\n" ++ ansi.RESET ++ "{s}\n", .{name});
        println(stdout, ansi.BOLD ++ "Description\n" ++ ansi.RESET ++ "{s}\n", .{description});
        println(stdout, ansi.BOLD ++ "Type\n" ++ ansi.RESET ++ "{s}\n", .{opt.type});
        println(stdout, ansi.BOLD ++ "Default\n" ++ ansi.RESET ++ "{s}\n", .{default});
        if (example) |e| {
            println(stdout, ansi.BOLD ++ "Example\n" ++ ansi.RESET ++ "{s}\n", .{e});
        }
        if (opt.declarations.len > 0) {
            println(stdout, ansi.BOLD ++ "Declared In" ++ ansi.RESET, .{});
            for (opt.declarations) |decl| {
                println(stdout, ansi.ITALIC ++ "  - {s}" ++ ansi.RESET, .{decl});
            }
        }
        if (opt.readOnly) {
            println(stdout, ansi.RED ++ ansi.ITALIC ++ "\nThis option is read-only." ++ ansi.RESET, .{});
        }
    } else {
        println(stdout, "Name\n{s}\n", .{name});
        println(stdout, "Description\n{s}\n", .{description});
        println(stdout, "Type\n{s}\n", .{opt.type});
        println(stdout, "Default\n{s}\n", .{default});
        if (example) |e| {
            println(stdout, "Example\n{s}\n", .{e});
        }
        if (opt.declarations.len > 0) {
            println(stdout, "Declared In", .{});
            for (opt.declarations) |decl| {
                println(stdout, "  - {s}", .{decl});
            }
        }
        if (opt.readOnly) {
            println(stdout, "\nThis option is read-only.", .{});
        }
    }
}

const prebuilt_options_cache_filename = Constants.current_system ++ "/etc/nixos-cli/options-cache.json";

fn option(allocator: Allocator, args: OptionCommand) !void {
    if (!fileExistsAbsolute(Constants.etc_nixos)) {
        log.err("the option command is unsupported on non-NixOS systems", .{});
        return OptionError.UnsupportedOs;
    }

    var options_filename_alloc = false;
    const options_filename = blk: {
        if (!args.no_cache and fileExistsAbsolute(prebuilt_options_cache_filename)) {
            break :blk prebuilt_options_cache_filename;
        }
        options_filename_alloc = true;
        log.info("building option list cache, please wait...", .{});
        break :blk try findNixosOptionFilepath(allocator, args.includes.items);
    };
    defer if (options_filename_alloc) allocator.free(options_filename);

    var parsed_options = loadOptionsFromFile(allocator, options_filename) catch return OptionError.NoOptionCache;
    defer parsed_options.deinit();

    // NOTE: Is this really faster than just using the slice directly?
    // Need to benchmark.
    var options_list = std.MultiArrayList(NixosOption){};
    defer options_list.deinit(allocator);
    try options_list.setCapacity(allocator, parsed_options.value.len);
    for (parsed_options.value) |opt| {
        options_list.appendAssumeCapacity(opt);
    }

    if (args.interactive) {
        optionSearchUI(allocator, parsed_options.value) catch return OptionError.ResourceAccessFailed;
        return;
    }

    const option_input = args.option.?;
    const stdout = io.getStdOut().writer();

    for (options_list.items(.name), 0..) |opt_name, i| {
        const key = opt_name;

        if (mem.eql(u8, option_input, key)) {
            const value = options_list.get(i);
            if (args.json) {
                const output = .{
                    .name = key,
                    .description = if (value.description) |d| mem.trim(u8, d, "\n ") else null,
                    .type = value.type,
                    .default = if (value.default) |d| d.text else null,
                    .example = if (value.example) |e| e.text else null,
                    .declarations = value.declarations,
                    .readOnly = value.readOnly,
                };

                json.stringify(output, .{ .whitespace = .indent_2 }, stdout) catch unreachable;
                println(stdout, "", .{});
            } else {
                displayOption(key, value);
            }
            return;
        }
    } else {
        const candidate_filter_buf = try allocator.alloc(search.Candidate, options_list.len);
        defer allocator.free(candidate_filter_buf);

        const similar_options = blk: {
            const raw_filtered = search.rankCandidates(candidate_filter_buf, options_list.items(.name), &.{option_input}, false, true, true);
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
            println(stdout, "", .{});
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
        OptionError.ResourceAccessFailed => return 4,
        else => return 1,
    };

    return 0;
}

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

const config = @import("config.zig");

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
    value_only: bool = false,

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
        \\    -v, --value-only        Show only the selected option's value
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
            } else if (argIs(arg, "--value-only", "-v")) {
                parsed.value_only = true;
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
        if (parsed.interactive and parsed.value_only) {
            argError("--interactive and --value-only flags conflict", .{});
            return ArgParseError.ConflictingOptions;
        }
        if (parsed.json and parsed.value_only) {
            argError("--json and --value-only flags conflict", .{});
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

fn findNixosOptionFilepath(allocator: Allocator, configuration: ConfigType) ![]const u8 {
    const option_cache_expr = switch (configuration) {
        .flake => |ref| try fmt.allocPrint(allocator, flake_options_cache_expr, .{ ref.uri, ref.system }),
        .legacy => try allocator.dupe(u8, legacy_options_cache_expr),
    };
    defer allocator.free(option_cache_expr);

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix-build", "--no-out-link", "--expr", option_cache_expr });

    if (std.meta.activeTag(configuration) == .legacy) {
        for (configuration.legacy) |include| {
            try argv.appendSlice(&.{ "-I", include });
        }
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

const annotations_to_remove: []const []const u8 = &.{
    "{option}`",
    "{var}`",
    "{file}`",
    "{env}`",
    "{command}`",
    "{manpage}`",
};

/// Some options have annotations in the form of {manpage}`hello(1)`, or
/// {option}`system.nixos.version`, or similar. Remove these, as they can
/// obscure plain text.
pub fn stripInlineCodeAnnotations(slice: []const u8, buf: []u8) []const u8 {
    var result: []const u8 = slice;

    for (annotations_to_remove) |input| {
        const new_size = std.mem.replacementSize(u8, result, input, "`");
        _ = std.mem.replace(u8, result, input, "`", buf);
        result = buf[0..new_size];
    }

    return result;
}

fn displayOption(allocator: Allocator, opt: NixosOption, evaluated: EvaluatedValue) !void {
    const c = config.getConfig();

    const stdout = io.getStdOut().writer();

    const desc_buf = try allocator.alloc(u8, if (opt.description) |d| d.len else 0);
    defer allocator.free(desc_buf);

    // A lot of attributes have lots of newlines and spaces,
    // especially trailing ones. This should be trimmed.
    var desc_alloc: bool = false;
    const description = blk: {
        if (opt.description) |d| {
            const stripped = stripInlineCodeAnnotations(d, desc_buf);

            // Skip rendering if NO_COLOR is set, or if prettifying
            // is disabled in the config. This isn't worth the time
            // to try and parse and format properly without the ANSI escapes.
            //
            // If a generic writer is brought in that sanitizes all ANSI
            // codes, then this can be revisited.
            if (!Constants.use_color or !c.option.prettify) {
                break :blk mem.trim(u8, stripped, "\n");
            }

            const rendered = utils.markdown.renderMarkdownANSI(allocator, stripped) catch |err| {
                desc_alloc = true;
                break :blk try fmt.allocPrint(allocator, "unable to render description: {s}", .{@errorName(err)});
            };
            desc_alloc = true;
            break :blk mem.trim(u8, rendered, "\n ");
        }

        break :blk ansi.ITALIC ++ "(none)" ++ ansi.RESET;
    };
    defer if (desc_alloc) allocator.free(description);

    const default = blk: {
        if (opt.default) |d| {
            break :blk mem.trim(u8, d.text, "\n ");
        }
        break :blk "(none)";
    };
    const example = if (opt.example) |e| mem.trim(u8, e.text, "\n ") else null;

    println(stdout, ansi.BOLD ++ "Name\n" ++ ansi.RESET ++ "{s}\n", .{opt.name});
    println(stdout, ansi.BOLD ++ "Description\n" ++ ansi.RESET ++ "{s}\n", .{description});
    println(stdout, ansi.BOLD ++ "Type\n" ++ ansi.RESET ++ ansi.ITALIC ++ "{s}\n" ++ ansi.RESET, .{opt.type});
    println(stdout, ansi.BOLD ++ "Value" ++ ansi.RESET, .{});
    if (std.meta.activeTag(evaluated) == .success) {
        println(stdout, "{s}\n", .{evaluated.success});
    } else {
        println(stdout, ansi.RED ++ "error: {s}\n" ++ ansi.RESET, .{evaluated.@"error"});
    }

    println(stdout, ansi.BOLD ++ "Default" ++ ansi.RESET, .{});
    if (opt.default) |_| {
        println(stdout, ansi.WHITE ++ "{s}" ++ ansi.RESET, .{default});
    } else {
        println(stdout, ansi.ITALIC ++ "(none)" ++ ansi.RESET, .{});
    }
    println(stdout, "", .{});

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
        println(stdout, ansi.YELLOW ++ "\nThis option is read-only." ++ ansi.RESET, .{});
    }
}

pub fn evaluateOptionValue(allocator: Allocator, configuration: ConfigType, name: []const u8) !EvaluatedValue {
    switch (configuration) {
        .flake => |ref| {
            const attr = try fmt.allocPrint(allocator, "{s}#nixosConfigurations.{s}.config.{s}", .{ ref.uri, ref.system, name });
            defer allocator.free(attr);

            const argv = &.{ "nix", "eval", attr };

            const result = utils.runCmd(.{
                .allocator = allocator,
                .argv = argv,
                .stderr_type = .Ignore,
            }) catch |err| return .{ .@"error" = try fmt.allocPrint(allocator, "unable to run `nix eval`: {s}", .{@errorName(err)}) };
            if (result.status != 0) {
                // TODO: add error trace from `nix eval`
                return .{ .@"error" = try fmt.allocPrint(allocator, "`nix eval` exited with status {d}", .{result.status}) };
            }

            return .{ .success = result.stdout.? };
        },
        .legacy => |includes| {
            var argv = ArrayList([]const u8).init(allocator);
            defer argv.deinit();

            const attr = try fmt.allocPrint(allocator, "config.{s}", .{name});
            defer allocator.free(attr);

            try argv.appendSlice(&.{ "nix-instantiate", "--eval", "<nixpkgs/nixos>", "-A", attr });
            for (includes) |include| {
                try argv.append(include);
            }

            const result = utils.runCmd(.{
                .allocator = allocator,
                .argv = argv.items,
                .stderr_type = .Ignore,
            }) catch |err| return .{ .@"error" = try fmt.allocPrint(allocator, "unable to run `nix-instantiate`: {s}", .{@errorName(err)}) };
            if (result.status != 0) {
                // TODO: add error trace from `nix-instantiate`
                return .{ .@"error" = try fmt.allocPrint(allocator, "`nix-instantiate` exited with status {d}", .{result.status}) };
            }

            return .{ .success = result.stdout.? };
        },
    }
}

pub const ConfigType = union(enum) {
    legacy: []const []const u8,
    flake: utils.FlakeRef,
};

pub const EvaluatedValue = union(enum) {
    loading,
    success: []const u8,
    @"error": []const u8,
};

pub const OptionCandidate = utils.search.CandidateStruct(NixosOption);

pub fn compareOptionCandidates(_: void, a: OptionCandidate, b: OptionCandidate) bool {
    if (a.rank < b.rank) return true;
    if (a.rank > b.rank) return false;

    const aa = a.value.name;
    const bb = b.value.name;

    if (aa.len < bb.len) return true;
    if (aa.len > bb.len) return false;

    for (aa, 0..) |c, i| {
        if (c < bb[i]) return true;
        if (c > bb[i]) return false;
    }

    return false;
}

const prebuilt_options_cache_filename = Constants.current_system ++ "/etc/nixos-cli/options-cache.json";

fn option(allocator: Allocator, args: OptionCommand) !void {
    if (!fileExistsAbsolute(Constants.etc_nixos)) {
        log.err("the option command is unsupported on non-NixOS systems", .{});
        return OptionError.UnsupportedOs;
    }

    var hostname_buf: [posix.HOST_NAME_MAX]u8 = undefined;
    const configuration: ConfigType = blk: {
        if (opts.flake) {
            var flake_ref = utils.findFlakeRef() catch return error.UnknownFlakeRef;
            flake_ref.inferSystemNameIfNeeded(&hostname_buf) catch return error.UnknownFlakeRef;
            break :blk .{ .flake = flake_ref };
        }
        break :blk .{ .legacy = args.includes.items };
    };

    var options_filename_alloc = false;
    const options_filename = blk: {
        if (!args.no_cache and fileExistsAbsolute(prebuilt_options_cache_filename)) {
            break :blk prebuilt_options_cache_filename;
        }
        options_filename_alloc = true;
        log.info("building option list cache, please wait...", .{});
        break :blk try findNixosOptionFilepath(allocator, configuration);
    };
    defer if (options_filename_alloc) allocator.free(options_filename);

    var parsed_options = loadOptionsFromFile(allocator, options_filename) catch return OptionError.NoOptionCache;
    defer parsed_options.deinit();

    const options_list = parsed_options.value;

    if (args.interactive) {
        optionSearchUI(allocator, configuration, options_list, args.option) catch return OptionError.ResourceAccessFailed;
        return;
    }

    const option_input = args.option.?;
    const stdout = io.getStdOut().writer();

    for (options_list) |opt| {
        if (mem.eql(u8, option_input, opt.name)) {
            const value = try evaluateOptionValue(allocator, configuration, opt.name);
            defer switch (value) {
                .loading => unreachable,
                .@"error" => |payload| allocator.free(payload),
                .success => |payload| allocator.free(
                    payload,
                ),
            };

            if (args.json) {
                const output = .{
                    .name = opt.name,
                    .description = if (opt.description) |d| mem.trim(u8, d, "\n ") else null,
                    .type = opt.type,
                    .value = switch (value) {
                        .loading => unreachable,
                        .@"error" => null,
                        .success => |payload| payload,
                    },
                    .default = if (opt.default) |d| mem.trim(u8, d.text, "\n") else null,
                    .example = if (opt.example) |e| mem.trim(u8, e.text, "\n") else null,
                    .declarations = opt.declarations,
                    .readOnly = opt.readOnly,
                };

                json.stringify(output, .{ .whitespace = .indent_2 }, stdout) catch unreachable;
                println(stdout, "", .{});
            } else if (args.value_only) {
                if (std.meta.activeTag(value) == .success) {
                    println(stdout, "{s}", .{value.success});
                } else {
                    log.err("{s}", .{value.@"error"});
                    return OptionError.ResourceAccessFailed;
                }
            } else {
                try displayOption(allocator, opt, value);
            }
            return;
        }
    } else {
        const candidate_filter_buf = try allocator.alloc(OptionCandidate, options_list.len);
        defer allocator.free(candidate_filter_buf);

        const tokens = try utils.splitScalarAlloc(allocator, option_input, ' ');
        defer allocator.free(tokens);

        const similar_options = blk: {
            const raw_filtered = search.rankCandidatesStruct(NixosOption, "name", candidate_filter_buf, options_list, tokens, true, true);
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
                dst.* = opt_name.value.name;
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
                    log.print("  - {s}\n", .{c.value.name});
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

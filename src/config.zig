const std = @import("std");
const mem = std.mem;
const json = std.json;
const posix = std.posix;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const Constants = @import("constants.zig");

const log = @import("log.zig");

const toml = @import("toml");

const utils = @import("utils.zig");
const ansi = utils.ansi;
const fileExistsAbsolute = utils.fileExistsAbsolute;
const readFile = utils.readFile;

/// Given a path to a field inside a struct separated by periods,
/// try to set the field at this path to the provided value.
fn setFieldValue(comptime T: type, path: []const u8, value: []const u8, ptr: *T) !void {
    if (T == toml.Table or T == ?toml.Table) {
        log.err("setting dynamic config values is currently unsupported", .{});
        return error.DynamicField;
    }

    switch (@typeInfo(T)) {
        .Struct => |structInfo| {
            inline for (structInfo.fields) |field| {
                if (std.mem.startsWith(u8, path, field.name)) {
                    const rest = path[field.name.len..];

                    if (rest.len == 0) {
                        if (field.type == bool) {
                            const parsed = blk: {
                                if (mem.eql(u8, value, "true")) break :blk true;
                                if (mem.eql(u8, value, "false")) break :blk false;

                                return error.InvalidBoolean;
                            };

                            @field(ptr, field.name) = parsed;
                        } else if (field.type == []const u8 or field.type == ?[]const u8) {
                            // Empty values translate to null; there are no config fields that allow
                            // empty values in the configuration.
                            if (field.type == ?[]const u8 and value.len == 0) {
                                @field(ptr, field.name) = null;
                            } else {
                                @field(ptr, field.name) = value;
                            }

                            return;
                        } else if (field.type == f64) {
                            @field(ptr, field.name) = std.fmt.parseFloat(f64, value) catch return error.InvalidFloat;
                        } else {
                            return error.UnsupportedType;
                        }

                        return;
                    } else if (rest[0] == '.') {
                        return setFieldValue(field.type, rest[1..], value, &@field(ptr, field.name));
                    }
                }
            } else {
                return error.NoPathExists;
            }
        },
        else => return,
    }
}

pub const Config = struct {
    aliases: ?toml.Table = null,
    apply: struct {
        imply_impure_with_tag: bool = false,
        specialisation: ?[]const u8 = null,
        use_nom: bool = false,
    } = .{},
    config_location: []const u8 = "/etc/nixos",
    enter: struct {
        mount_resolv_conf: bool = true,
    } = .{},
    init: struct {
        enable_xserver: bool = false,
        desktop_config: ?[]const u8 = null,
        extra_attrs: ?toml.Table = null,
        extra_config: ?[]const u8 = null,
    } = .{},
    no_confirm: bool = false,
    option: struct {
        max_rank: f64 = 3.00,
        prettify: bool = true,
    } = .{},
    use_nvd: bool = false,
};

var parsed_config: ?toml.Parsed(Config) = null;
var config: Config = Config{};

pub fn getConfig() Config {
    return config;
}

pub fn validateConfig(allocator: Allocator) !void {
    const cfg = &config;

    if (cfg.aliases) |*aliases| {
        var values_to_remove = ArrayList([]const u8).init(allocator);
        defer values_to_remove.deinit();

        var it = aliases.iterator();

        while (it.next()) |kv| {
            const key = kv.key_ptr.*;
            const value = kv.value_ptr.*;

            if (key.len == 0) {
                configError("aliases: alias name cannot be empty", .{});
                try values_to_remove.append(key);
            } else if (mem.startsWith(u8, key, "-")) {
                configError("aliases: alias '{s}' cannot start with a '-'", .{key});
                try values_to_remove.append(key);
            } else if (mem.indexOfAny(u8, key, &std.ascii.whitespace) != null) {
                configError("aliases: alias '{s}' cannot have whitespace", .{key});
                try values_to_remove.append(key);
            } else if (std.meta.activeTag(value) != .array) {
                configError("aliases.{s}: expected type array, got type {s}", .{ key, @tagName(value) });
                try values_to_remove.append(key);
            } else if (value.array.items.len == 0) {
                configError("aliases.{s}: args list cannot be empty", .{key});
                try values_to_remove.append(key);
            } else {
                for (value.array.items) |arg| {
                    if (std.meta.activeTag(arg) != .string) {
                        configError("aliases.{s}: expected type string for args array, got type {s}", .{ key, @tagName(arg) });
                        try values_to_remove.append(key);
                        break;
                    }
                }
            }
        }

        for (values_to_remove.items) |key| {
            _ = aliases.remove(key);
        }
    }

    if (cfg.option.max_rank < 1.00) {
        log.err("option: max_rank must be at least 1.00", .{});
        cfg.option.max_rank = 3.00;
    }
}

pub fn parseConfig(allocator: Allocator) !void {
    const config_location = posix.getenv("NIXOS_CLI_CONFIG") orelse Constants.default_config_location;

    const config_str = readFile(allocator, config_location) catch |err| {
        log.err("error opening config: {s}", .{@errorName(err)});
        return err;
    };
    defer allocator.free(config_str);

    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();

    const parsed = parser.parseString(config_str) catch |err| {
        log.err("unable to parse settings: {s}", .{@errorName(err)});
        return err;
    };
    errdefer deinit();

    parsed_config = parsed;
    config = parsed.value;
}

/// Set a config value based on a key=value pair. This is sourced
/// from the command-line args.
pub fn setConfigValue(pair: []const u8) !void {
    const split_idx = mem.indexOf(u8, pair, "=") orelse {
        log.err("command-line config values must be specified in <KEY>=<VALUE> format", .{});
        return error.InvalidValue;
    };

    const path = pair[0..split_idx];
    const value = pair[split_idx + 1 ..];

    // TODO: handle missing config correctly
    setFieldValue(Config, path, value, &config) catch |err| {
        switch (err) {
            error.UnsupportedType => log.err("setting with path '{s}' cannot be set outside configuration", .{path}),
            error.DynamicField => log.err("setting values for '{s}' is unsupported", .{path}),
            error.NoPathExists => log.err("setting with path '{s}' does not exist", .{path}),
            error.InvalidBoolean => log.err("{s}: expected boolean, got invalid value '{s}'", .{ path, value }),
            error.InvalidFloat => log.err("{s}: expected number, got invalid value '{s}'", .{ path, value }),
        }
        return err;
    };
}

pub fn deinit() void {
    if (parsed_config) |value| {
        value.deinit();
        parsed_config = null;
    }
}

fn configError(comptime fmt: []const u8, args: anytype) void {
    if (Constants.use_color) {
        log.print(ansi.BOLD ++ ansi.RED ++ "error" ++ ansi.RESET ++ ": ", .{});
    } else {
        log.print("error: ", .{});
    }
    log.print("invalid setting: ", .{});
    log.print(fmt ++ "\n", args);
}

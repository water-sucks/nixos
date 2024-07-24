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
};

var config_value: ?toml.Parsed(Config) = null;

pub fn getConfig() Config {
    return if (config_value) |parsed| parsed.value else Config{};
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
    var config = parsed.value;

    // Validation
    if (config.aliases) |*aliases| {
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

    if (config.init.extra_attrs) |*extra_attrs| {
        var values_to_remove = ArrayList([]const u8).init(allocator);
        defer values_to_remove.deinit();

        var it = extra_attrs.iterator();
        while (it.next()) |kv| {
            const key = kv.key_ptr.*;
            const value = kv.value_ptr.*;

            if (std.meta.activeTag(value) != .string) {
                configError("init.extra_attrs: expected type string for key '{s}', got type {s}", .{ key, @tagName(value) });
                try values_to_remove.append(key);
            }
        }

        for (values_to_remove.items) |key| {
            _ = extra_attrs.remove(key);
        }
    }

    config_value = parsed;
}

pub fn deinit() void {
    if (config_value) |value| {
        value.deinit();
        config_value = null;
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

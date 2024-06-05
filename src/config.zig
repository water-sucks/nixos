const std = @import("std");
const mem = std.mem;
const json = std.json;
const Allocator = mem.Allocator;

const Constants = @import("constants.zig");

const log = @import("log.zig");

const toml = @import("toml");

const utils = @import("utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;
const readFile = utils.readFile;

pub const Alias = struct {
    /// Name of alias on command line; must not contain spaces
    alias: []const u8,
    /// What to resolve alias to on command line
    resolve: []const []const u8,
};

pub const KVPair = struct {
    name: []const u8,
    value: []const u8,
};

pub const Config = struct {
    aliases: ?[]Alias = null,
    apply: struct {
        specialisation: ?[]const u8 = null,
        config_location: []const u8 = "/etc/nixos",
        use_nom: bool = false,
    } = .{},
    enter: struct {
        mount_resolv_conf: bool = true,
    } = .{},
    init: struct {
        enable_xserver: bool = false,
        desktop_config: ?[]const u8 = null,
        extra_attrs: ?[]KVPair = null,
        extra_config: ?[]const u8 = null,
    } = .{},
};

pub const ParseConfigError = error{
    InvalidValue,
};

var config_value: ?toml.Parsed(Config) = null;

pub fn getConfig() Config {
    return if (config_value) |parsed| parsed.value else Config{};
}

pub fn parseConfig(allocator: Allocator) !void {
    const config_location = Constants.config_location ++ "/config.toml";

    const config_str = readFile(allocator, config_location) catch |err| {
        switch (err) {
            error.FileNotFound => return,
            else => log.err("error opening config: {s}", .{@errorName(err)}),
        }
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
    const config = parsed.value;

    // Validation
    if (config.aliases) |aliases| {
        for (aliases) |kv| {
            if (kv.alias.len == 0) {
                configError("alias name cannot be empty", .{});
                return ParseConfigError.InvalidValue;
            } else if (kv.resolve.len == 0) {
                configError("alias value cannot be empty", .{});
                return ParseConfigError.InvalidValue;
            } else if (mem.startsWith(u8, kv.alias, "-")) {
                configError("alias '{s}' cannot start with a '-'", .{kv.alias});
                return ParseConfigError.InvalidValue;
            } else if (mem.indexOfAny(u8, kv.alias, &std.ascii.whitespace) != null) {
                configError("alias '{s}' cannot have whitespace", .{kv.alias});
                return ParseConfigError.InvalidValue;
            }
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
    log.print("error: invalid setting: ", .{});
    log.print(fmt ++ "\n", args);
    log.print("\nFor more information, run `nixos --help`.\n", .{});
}

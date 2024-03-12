const std = @import("std");
const mem = std.mem;
const json = std.json;
const Allocator = mem.Allocator;
const ParsedJson = json.Parsed;

const Constants = @import("constants.zig");

const log = @import("log.zig");

const utils = @import("utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;
const readFile = utils.readFile;

pub const Alias = struct {
    /// Name of alias on command line; must not contain spaces
    alias: []const u8,
    /// What to resolve alias to on command line
    resolve: []const u8,
};

const KVPair = struct {
    name: []const u8,
    value: []const u8,
};

pub const Config = struct {
    aliases: ?[]Alias = null,
    apply: struct {
        specialisation: ?[]const u8 = null,
        config_location: []const u8 = "/etc/nixos",
    } = .{},
    enter: struct {
        mount_resolv_config: bool = true,
    } = .{},
    init: struct {
        enable_xserver: bool = false,
        desktop_config: ?[]const u8 = null,
        extra_attrs: ?[]KVPair = null,
        extra_config: ?[]const u8 = null,
    } = .{},
};

var config_value: ?ParsedJson(Config) = null;

pub fn getConfig() Config {
    return if (config_value) |parsed| parsed.value else Config{};
}

pub fn parseConfig(allocator: Allocator) !void {
    const config_location = Constants.config_location ++ "/config.json";
    const config_str = readFile(allocator, config_location) catch |err| {
        switch (err) {
            error.FileNotFound => {
                // Use default config if config is not found.
                return;
            },
            else => log.err("error opening config: {s}", .{@errorName(err)}),
        }
        return err;
    };
    defer allocator.free(config_str);
    config_value = try json.parseFromSlice(Config, allocator, config_str, .{ .ignore_unknown_fields = true });
}

pub fn deinit() void {
    if (config_value) |value| {
        value.deinit();
        config_value = null;
    }
}

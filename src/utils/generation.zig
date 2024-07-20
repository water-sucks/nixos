const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const json = std.json;
const mem = std.mem;
const Allocator = mem.Allocator;

const log = @import("../log.zig");

const utils = @import("../utils.zig");
const date = utils.date;

/// This is the parsed info the nixos-version.json generation file at the
/// root of each generation created with the `nixos-cli` module contains.
pub const GenerationInfo = struct {
    nixosVersion: ?[]const u8 = null,
    nixpkgsRevision: ?[]const u8 = null,
    configurationRevision: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

/// Detailed Metadata about a NixOS generation
pub const GenerationMetadata = struct {
    allocator: Allocator,

    /// Generation number
    generation: ?usize = null,
    /// Date of generation creation
    date: ?date.TimeStamp = null,
    /// If this generation is the currently activated one
    current: bool = false,
    /// NixOS version of generation
    nixos_version: ?[]const u8 = null,
    /// nixpkgs revision (if it exists)
    nixpkgs_revision: ?[]const u8 = null,
    /// Version of active kernel in generation
    kernel_version: ?[]const u8 = null,
    /// Configuration revision (if it exists)
    configuration_revision: ?[]const u8 = null,
    /// Generation specialisation (if not base config)
    specialisations: ?[][]const u8 = null,

    const Self = @This();

    /// Caller owns returned memory, free with .deinit(allocator).
    /// This is a utility function to construct generation information,
    /// and as such will panic, log to stdout, and return errors in
    /// certain instances. This is behavior to take into account when
    /// consuming this externally, if that ever happens (I doubt it!).
    pub fn getGenerationInfo(allocator: Allocator, path: fs.Dir, gen_number: ?usize) !Self {
        var result: GenerationMetadata = GenerationMetadata{
            .allocator = allocator,
            .generation = gen_number,
        };
        errdefer result.deinit();

        // Read NixOS version from nixos-version file for configuration rev
        const nixos_version_contents = blk: {
            const file = path.openFile("nixos-version.json", .{}) catch |err| {
                log.err("unable to open nixos-version.json for generation {?d}: {s}", .{ gen_number, @errorName(err) });
                break :blk null;
            };
            defer file.close();

            var reader = json.reader(allocator, file.reader());
            defer reader.deinit();

            break :blk json.parseFromTokenSource(GenerationInfo, allocator, &reader, .{
                .allocate = .alloc_always,
            }) catch |err| {
                log.err("unable to parse nixos-version.json for generation {?d}: {s}", .{ gen_number, @errorName(err) });
                break :blk null;
            };
        };
        defer if (nixos_version_contents) |contents| contents.deinit();
        const nixos_version_info: GenerationInfo = if (nixos_version_contents) |contents| contents.value else GenerationInfo{};
        if (nixos_version_info.nixosVersion) |version| {
            result.nixos_version = try allocator.dupe(u8, version);
        }
        if (nixos_version_info.configurationRevision) |rev| {
            result.configuration_revision = try allocator.dupe(u8, rev);
        }
        if (nixos_version_info.nixpkgsRevision) |rev| {
            result.nixpkgs_revision = try allocator.dupe(u8, rev);
        }

        if (result.nixos_version == null) {
            const nixos_version_file = path.openFile("nixos-version", .{}) catch |err| blk: {
                log.err("unable to open nixos-version file for generation {?d}: {s}", .{ gen_number, @errorName(err) });
                break :blk null;
            };
            if (nixos_version_file) |file| {
                defer file.close();
                result.nixos_version = file.readToEndAlloc(allocator, 1000) catch null;
            }
        }

        // Get time of creation for generation
        // (uses ctime, so may be inaccurate if tampered with)
        const gen_stat = path.stat() catch |err| blk: {
            log.err("unable to stat generation {?d} dir to find last modified time: {s}", .{ gen_number, @errorName(err) });
            break :blk null;
        };
        if (gen_stat) |stat| {
            result.date = date.TimeStamp.fromEpochTime(@intCast(stat.ctime));
        }

        // Get kernel version of generation from lib/modules/${version} directory
        // This version directory should exist, but on the off chance it doesn't,
        // don't take chances.
        var kernel_dir = path.openDir("kernel-modules/lib/modules", .{ .iterate = true }) catch |err| blk: {
            log.err("unexpected error encountered opening kernel-modules/lib/modules for generation {?d}: {s}", .{ gen_number, @errorName(err) });
            break :blk null;
        };
        if (kernel_dir) |*dir| {
            defer dir.close();
            var iter = dir.iterate();

            const version_dir = iter.next() catch @panic("could not iterate kernel modules dir");

            if (version_dir) |version| {
                result.kernel_version = try allocator.dupe(u8, fs.path.basename(version.name));
            }
        }

        var specialisation_dir = path.openDir("specialisation", .{ .iterate = true }) catch |err| blk: {
            log.err("unexpected error encountered opening specialisations dir for generation {?d}: {s}", .{ gen_number, @errorName(err) });
            break :blk null;
        };
        if (specialisation_dir) |*dir| {
            defer dir.close();

            var specializations_list = std.ArrayList([]const u8).init(allocator);
            errdefer specializations_list.deinit();
            errdefer {
                for (specializations_list.items) |s| {
                    allocator.free(s);
                }
            }

            var iter = dir.iterate();
            while (iter.next() catch @panic("unable to access specialisation dir")) |entry| {
                try specializations_list.append(try allocator.dupe(u8, entry.name));
            }

            result.specialisations = try specializations_list.toOwnedSlice();
            mem.sort([]const u8, result.specialisations.?, {}, utils.stringLessThan);
        }

        return result;
    }

    pub fn lessThan(_: void, lhs: GenerationMetadata, rhs: GenerationMetadata) bool {
        return lhs.generation orelse 0 < rhs.generation orelse 0;
    }

    // Explicitly pass the allocator here in order to avoid
    // JSON serialization problems.
    pub fn deinit(self: *Self) void {
        if (self.nixos_version) |version| self.allocator.free(version);
        if (self.kernel_version) |version| self.allocator.free(version);
        if (self.nixpkgs_revision) |rev| self.allocator.free(rev);
        if (self.configuration_revision) |rev| self.allocator.free(rev);

        if (self.specialisations) |specialisations| {
            for (specialisations) |s| {
                self.allocator.free(s);
            }
            self.allocator.free(specialisations);
        }
    }

    pub fn jsonStringify(self: Self, out: anytype) !void {
        try out.beginObject();

        if (self.generation) |gen| {
            try out.objectField("generation");
            try out.write(gen);
        }

        try out.objectField("date");
        if (self.date) |d| {
            // error.OutOfMemory is not allowed in this error union.
            const formatted_date = d.toDateISO8601(self.allocator) catch return error.SystemResources;
            defer self.allocator.free(formatted_date);
            try out.write(formatted_date);
        } else {
            try out.write(null);
        }

        try out.objectField("current");
        try out.write(self.current);

        try out.objectField("nixos_version");
        try out.write(self.nixos_version);

        try out.objectField("kernel_version");
        try out.write(self.kernel_version);

        try out.objectField("nixpkgs_revision");
        try out.write(self.nixpkgs_revision);

        try out.objectField("configuration_revision");
        try out.write(self.configuration_revision);

        try out.objectField("specialisations");
        try out.write(self.specialisations);

        try out.endObject();
    }
};

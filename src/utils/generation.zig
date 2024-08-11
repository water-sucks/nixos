const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const json = std.json;
const mem = std.mem;
const posix = std.posix;
const sort = std.sort;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const log = @import("../log.zig");

const utils = @import("../utils.zig");
const ansi = utils.ansi;

const zeit = @import("zeit");

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
    date: ?zeit.Time = null,
    /// If this generation is the currently activated one
    current: bool = false,
    /// NixOS version of generation
    nixos_version: ?[]const u8 = null,
    /// Description of generation, if given
    description: ?[]const u8 = null,
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
        if (nixos_version_info.description) |desc| {
            result.description = try allocator.dupe(u8, desc);
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
        if (gen_stat) |stat| blk: {
            const ctime = zeit.instant(.{ .source = .{ .unix_nano = stat.ctime } }) catch break :blk;

            const local_tz = zeit.local(allocator) catch break :blk;
            defer local_tz.deinit();

            result.date = ctime.in(&local_tz).time();
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
            sort.block([]const u8, result.specialisations.?, {}, utils.stringLessThan);
        }

        return result;
    }

    pub fn lessThan(_: void, lhs: GenerationMetadata, rhs: GenerationMetadata) bool {
        return lhs.generation orelse 0 < rhs.generation orelse 0;
    }

    pub fn prettyPrint(self: Self, options: struct {
        color: bool = true,
        show_current_marker: bool = true,
    }, writer: anytype) !void {
        const nixos_version = self.nixos_version orelse "NixOS";

        const show_current = self.current and options.show_current_marker;

        if (options.color) {
            try writer.print(ansi.BOLD ++ ansi.ITALIC ++ "{s}\n" ++ ansi.RESET, .{nixos_version});
        } else {
            try writer.print("{s}\n", .{nixos_version});
        }
        for (0..nixos_version.len) |_| {
            try writer.print("-", .{});
        }
        try writer.print("\n", .{});

        try prettyPrintKeyValue(writer, "Generation", self.generation, .{ .color = options.color });

        const formatted_date: ?[]const u8 = if (self.date) |date|
            try fmt.allocPrint(self.allocator, "{s} {d:0>2}, {d} {d:0>2}:{d:0>2}:{d:0>2}", .{ date.month.name(), date.day, date.year, date.hour, date.minute, date.second })
        else
            null;
        defer if (formatted_date) |date| self.allocator.free(date);
        try prettyPrintKeyValue(writer, "Creation Date", formatted_date, .{ .color = options.color });

        if (self.description) |_| {
            try prettyPrintKeyValue(writer, "Description", self.description, .{ .color = options.color });
        }

        try prettyPrintKeyValue(writer, "Nixpkgs Revision", self.nixpkgs_revision, .{ .color = options.color });
        try prettyPrintKeyValue(writer, "Config Revision", self.configuration_revision, .{ .color = options.color });
        try prettyPrintKeyValue(writer, "Kernel Version", self.kernel_version, .{ .color = options.color });

        const specialisations: ?[]const u8 = if (self.specialisations != null and self.specialisations.?.len > 0)
            try utils.concatStringsSep(self.allocator, self.specialisations orelse &.{}, ", ")
        else
            null;
        defer if (specialisations) |s| self.allocator.free(s);
        try prettyPrintKeyValue(writer, "Specialisations", specialisations, .{
            .color = options.color,
            .default = "(none)",
        });

        if (options.color) {
            if (show_current) {
                try writer.print(ansi.RED ++ ansi.BOLD ++ "This generation is currently active.\n" ++ ansi.RESET, .{});
            }
        } else {
            if (show_current) {
                try writer.print("This generation is currently active.\n", .{});
            }
        }
    }

    const key_column_length = std.fmt.comptimePrint("{d}", .{
        sort.max(
            comptime_int,
            &.{ "Generation".len, "Creation Date".len, "Nixpkgs Revision".len, "Kernel Version".len },
            {},
            sort.asc(comptime_int),
        ).? + 1,
    });

    fn prettyPrintKeyValue(writer: anytype, title: []const u8, value: anytype, options: struct {
        color: bool = true,
        default: []const u8 = "unknown",
    }) !void {
        if (options.color) {
            try writer.print(ansi.CYAN ++ "{s: <" ++ key_column_length ++ "}" ++ ansi.RESET ++ ":: ", .{title});
        } else {
            try writer.print("{s: <" ++ key_column_length ++ "}" ++ ":: ", .{title});
        }

        const typ = @TypeOf(value);

        if (typ == ?usize) {
            if (options.color) {
                if (value) |v| {
                    try writer.print(ansi.ITALIC ++ "{d}" ++ ansi.RESET ++ "\n", .{v});
                } else {
                    try writer.print(ansi.ITALIC ++ "{s}" ++ ansi.RESET ++ "\n", .{options.default});
                }
            } else {
                if (value) |v| {
                    try writer.print("{d}\n", .{v});
                } else {
                    try writer.print("{s}\n", .{options.default});
                }
            }
        } else if (typ == ?[]const u8) {
            if (options.color) {
                try writer.print(ansi.ITALIC ++ "{s}" ++ ansi.RESET ++ "\n", .{value orelse options.default});
            } else {
                try writer.print("{s}\n", .{value orelse options.default});
            }
        } else {
            @compileError("prettyPrintKeyValue can only take usize or []const u8 values");
        }
    }

    // Explicitly pass the allocator here in order to avoid
    // JSON serialization problems.
    pub fn deinit(self: *Self) void {
        if (self.nixos_version) |version| self.allocator.free(version);
        if (self.description) |desc| self.allocator.free(desc);
        if (self.nixpkgs_revision) |rev| self.allocator.free(rev);
        if (self.configuration_revision) |rev| self.allocator.free(rev);
        if (self.kernel_version) |version| self.allocator.free(version);

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
            // Avoid a + being inserted for i32 type for year
            const year: u32 = @intCast(d.year);
            // error.OutOfMemory is not allowed in this error union.
            const formatted_date = fmt.allocPrint(self.allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
                year,
                @intFromEnum(d.month),
                d.day,
                d.hour,
                d.minute,
                d.second,
            }) catch return error.SystemResources;
            defer self.allocator.free(formatted_date);
            try out.write(formatted_date);
        } else {
            try out.write(null);
        }

        try out.objectField("current");
        try out.write(self.current);

        try out.objectField("nixos_version");
        try out.write(self.nixos_version);

        try out.objectField("description");
        try out.write(self.description);

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

pub fn gatherGenerationsFromProfile(allocator: Allocator, profile_name: []const u8) ![]GenerationMetadata {
    const profile_dirname = if (mem.eql(u8, profile_name, "system"))
        "/nix/var/nix/profiles"
    else
        "/nix/var/nix/profiles/system-profiles";

    var generations: ArrayList(GenerationMetadata) = ArrayList(GenerationMetadata).init(allocator);
    errdefer {
        for (generations.items) |*generation| {
            generation.deinit();
        }
        generations.deinit();
    }

    var generations_dir = fs.cwd().openDir(profile_dirname, .{ .iterate = true }) catch |err| {
        log.err("unexpected error encountered opening {s}: {s}", .{ profile_dirname, @errorName(err) });
        return err;
    };
    defer generations_dir.close();

    var path_buf: [posix.PATH_MAX]u8 = undefined;

    const current_generation_dirname = try fs.path.join(allocator, &.{ profile_dirname, profile_name });
    defer allocator.free(current_generation_dirname);

    // Check if generation is the current generation
    const current_system_name = posix.readlink(current_generation_dirname, &path_buf) catch |err| {
        log.err("unable to readlink {s}: {s}", .{ current_generation_dirname, @errorName(err) });
        return err;
    };

    var iter = generations_dir.iterate();
    while (iter.next() catch |err| {
        log.err("unexpected error while reading profile directory: {s}", .{@errorName(err)});
        return err;
    }) |entry| {
        const prefix = try fmt.allocPrint(allocator, "{s}-", .{profile_name});
        defer allocator.free(prefix);

        // I hate no regexes in this language. Big sad.
        // This works around the fact that multiple profile
        // names can share the same prefix.
        if (mem.startsWith(u8, entry.name, prefix) and
            mem.endsWith(u8, entry.name, "-link") and
            prefix.len + 5 < entry.name.len)
        {
            const gen_number_slice = entry.name[(prefix.len)..mem.indexOf(u8, entry.name, "-link").?];

            // If the number parsed is not an integer, it contains a dash
            // and is from another profile, so it is skipped.
            // Also, might as well pass this to the generation info
            // function and avoid extra work re-parsing the number.
            const generation_number = std.fmt.parseInt(usize, gen_number_slice, 10) catch continue;

            const generation_dirname = try fs.path.join(allocator, &.{ profile_dirname, entry.name });
            defer allocator.free(generation_dirname);

            // Skipping generations with `continue` is not a good idea.
            // Many places in the code rely on the assumption that there
            // is *always* one current generation.
            var generation_dir = fs.openDirAbsolute(generation_dirname, .{}) catch |err| {
                log.err("unexpected error encountered opening {s}: {s}", .{ generation_dirname, @errorName(err) });
                return err;
            };
            defer generation_dir.close();

            var generation = try GenerationMetadata.getGenerationInfo(allocator, generation_dir, generation_number);
            errdefer generation.deinit();

            if (mem.eql(u8, current_system_name, entry.name)) {
                generation.current = true;
            }

            try generations.append(generation);
        }
    }

    mem.sort(GenerationMetadata, generations.items, {}, GenerationMetadata.lessThan);

    return try generations.toOwnedSlice();
}

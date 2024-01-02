const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const util = @import("./util.zig");
const NixContext = util.NixContext;

const errors = @import("./error.zig");
const nixError = errors.nixError;
const NixError = errors.NixError;

const libnix = @import("./c.zig").libnix;

/// Initialize the Nix store library. Call this before
/// creating a store; it can be called multiple times.
pub fn init(context: NixContext) NixError!void {
    const err = libnix.nix_libstore_init(context.context);
    if (err != 0) return nixError(err);
}

/// Load plugins specified in the settings. Call this
/// once, after calling the other init functions and setting
/// any desired settings.
pub fn initPlugins(context: NixContext) NixError!void {
    const err = libnix.nix_init_plugins(context.context);
    if (err != 0) return nixError(err);
}

pub const Store = struct {
    store: *libnix.Store,

    const Self = @This();

    /// Open a Nix store. Call `unref` after to release memory.
    pub fn open(allocator: Allocator, context: NixContext, uri: []const u8, options: anytype) !Self {
        _ = options;

        const uriZ = try allocator.dupeZ(u8, uri);
        defer allocator.free(uriZ);

        var new_store = libnix.nix_store_open(context.context, uriZ.ptr, null);
        if (new_store == null) {
            try context.errorCode(); // See if there was a Nix error first.
            return error.OutOfMemory; // Otherwise, probably out of memory.
        }

        return Self{ .store = new_store.? };
    }

    /// Get the version of a Nix store. Caller owns returned memory.
    pub fn getVersion(self: Self, allocator: Allocator, context: NixContext, max_bytes: c_uint) ![]u8 {
        if (max_bytes < 1) @panic("nixstore: nix_store_get_version: max_bytes cannot be < 1");

        var buf = try allocator.alloc(u8, @intCast(max_bytes));
        defer allocator.free(buf);

        const err = libnix.nix_store_get_version(context.context, self.store, buf.ptr, max_bytes);
        if (err != 0) return nixError(err);

        return try allocator.dupe(u8, mem.sliceTo(buf, 0));
    }

    /// Get the URI of a Nix store. Caller owns returned memory.
    pub fn getUri(self: Self, allocator: Allocator, context: NixContext, max_bytes: c_uint) ![]u8 {
        if (max_bytes < 1) @panic("nixstore: nix_store_get_uri: max_bytes cannot be < 1");

        var buf = try allocator.alloc(u8, @intCast(max_bytes));
        defer allocator.free(buf);

        const err = libnix.nix_store_get_uri(context.context, self.store, buf.ptr, max_bytes);
        if (err != 0) return nixError(err);

        return try allocator.dupe(u8, mem.sliceTo(buf, 0));
    }

    /// Retrieve a store path from a Nix store.
    pub fn parsePath(self: Self, allocator: Allocator, context: NixContext, path: []const u8) !StorePath {
        const pathZ = try allocator.dupeZ(u8, path);
        defer allocator.free(pathZ);

        const store_path = libnix.nix_store_parse_path(context.context, self.store, pathZ);
        if (store_path == null) {
            try context.errorCode(); // See if there was a Nix error first.
            return error.OutOfMemory; // Otherwise, probably out of memory.
        }

        return StorePath{
            .path = store_path.?,
            .store = self.store,
        };
    }

    /// Unref this Nix store. Does not fail; it'll be closed and
    /// deallocated when all references are gone.
    pub fn unref(self: Self) void {
        libnix.nix_store_unref(self.store);
    }
};

pub const StorePath = struct {
    path: *libnix.StorePath,
    store: *libnix.Store,

    const Self = @This();

    /// Check if this StorePath is valid (aka if exists in the referenced
    /// store). Error info is stored in the passed context.
    pub fn isValid(self: Self, context: NixContext) bool {
        const valid = libnix.nix_store_is_valid_path(context.context, self.store, self.path);
        return valid;
    }

    /// Realize a Nix store path. This is a blocking function.
    pub fn build(
        self: Self,
        context: NixContext,
        user_data: ?*anyopaque,
        callback: *const fn (user_data: ?*anyopaque, out_name: [*c]const u8, out: [*c]const u8) callconv(.C) void,
    ) NixError!void {
        const err = libnix.nix_store_build(context.context, self.store, self.path, user_data, callback);
        if (err != 0) return nixError(err);
    }

    // Deallocate this StorePath. Does not fail.
    pub fn deinit(self: Self) void {
        libnix.nix_store_path_free(self.path);
    }
};

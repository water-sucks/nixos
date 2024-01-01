const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const errors = @import("./error.zig");
const nixError = errors.nixError;
const NixError = errors.NixError;

const libnix = @import("./c.zig").libnix;

/// Initialize libutil and its dependencies.
pub fn init(context: NixContext) NixError!void {
    const err = libnix.nix_libutil_init(context.context);
    if (err != 0) return nixError(err);
}

/// Retrieve the current libnix library version.
pub fn version() []const u8 {
    return mem.span(libnix.nix_version_get());
}

pub const settings = struct {
    /// Retrieve a setting from the Nix global configuration.
    /// Caller owns returned memory.
    pub fn get(allocator: Allocator, context: NixContext, key: []const u8, max_bytes: c_int) ![]u8 {
        if (max_bytes < 1) @panic("nixutil: nix_setting_get: max_bytes cannot be < 1");

        var buf = try allocator.alloc(u8, @intCast(max_bytes));
        defer allocator.free(buf);

        const keyz = try allocator.dupeZ(u8, key);
        defer allocator.free(keyz);

        const err = libnix.nix_setting_get(context.context, keyz.ptr, buf.ptr, max_bytes);
        if (err != 0) return nixError(err);

        return try allocator.dupe(u8, mem.sliceTo(buf, 0));
    }

    /// Set a setting in the Nix global configuration.
    pub fn set(allocator: Allocator, context: NixContext, key: []const u8, value: []const u8) !void {
        const keyz = try allocator.dupeZ(u8, key);
        defer allocator.free(keyz);

        const valuez = try allocator.dupeZ(u8, value);
        defer allocator.free(valuez);

        const err = libnix.nix_setting_set(context.context, keyz.ptr, valuez.ptr);
        if (err != 0) return nixError(err);
    }
};

pub const NixContext = struct {
    context: *libnix.nix_c_context,

    const Self = @This();

    /// Create an instance of NixContext. Caller must call deinit()
    /// to free memory with the underlying allocator.
    pub fn init() !Self {
        var new_context = libnix.nix_c_context_create();
        if (new_context == null) return error.OutOfMemory;

        return Self{
            .context = new_context.?,
        };
    }

    /// Retrieve the most recent error code from this context.
    pub fn errorCode(self: Self) NixError!void {
        const err = libnix.nix_err_code(self.context);
        if (err != 0) return nixError(err);
    }

    /// Retrieve the error message from errorInfo inside another context.
    /// Used to inspect Nix error messages; only call after the previous
    /// Nix function has returned `NixError.NixError`. Caller owns returned
    /// memory.
    pub fn errorInfoMessage(self: Self, allocator: Allocator, context: NixContext, max_bytes: c_int) ![]u8 {
        if (max_bytes < 1) @panic("nixutil: nix_err_info_msg: max_bytes cannot be < 1");

        const buf = try allocator.alloc(u8, @intCast(max_bytes));
        defer allocator.free(buf);

        const err = libnix.nix_err_info_msg(context.context, self.context, buf.ptr, max_bytes);
        if (err != 0) return nixError(err);

        return try allocator.dupe(u8, mem.sliceTo(buf, 0));
    }

    /// Retrieve the most recent error message directly from a context.
    /// Caller does not own returned memory.
    pub fn errorMessage(self: Self, context: NixContext) !?[]const u8 {
        const message = libnix.nix_err_msg(context.context, self.context, null);
        return if (message) |m| mem.span(m) else null;
    }

    /// Retrieve the error name from a context. Used to inspect Nix error
    /// messages; only call after the previous Nix function has returned
    /// `NixError.NixError`. Caller owns returned memory.
    pub fn errorName(self: Self, allocator: Allocator, context: NixContext, max_bytes: c_int) ![]u8 {
        if (max_bytes < 1) @panic("nixutil: nix_err_name: max_bytes cannot be < 1");

        const buf = try allocator.alloc(u8, @intCast(max_bytes));
        errdefer allocator.free(buf);

        const err = libnix.nix_err_name(context.context, self.context, buf.ptr, max_bytes);
        if (err != 0) return nixError(err);

        return try allocator.dupe(u8, mem.sliceTo(buf, 0));
    }

    /// Free the `NixContext`. Does not fail.
    pub fn deinit(self: Self) void {
        libnix.nix_c_context_free(self.context);
    }
};

const std = @import("std");
const posix = std.posix;
const mem = std.mem;

const whitespace = &std.ascii.whitespace;

/// While a `nixos` release is in development, this string should
/// contain the version in development with the "-dev" suffix.
/// When a release is tagged, the "-dev" suffix should be removed
/// for the commit that gets tagged. Directly after the tagged commit,
/// the version should be bumped and the "-dev" suffix added.
/// Thanks to `riverwm` for this idea for version number management.
const version = "0.6.0-dev";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zignix_package = b.dependency("zignix", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "nixos",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    exe.root_module.addImport("nix", zignix_package.module("zignix"));

    const full_version = blk: {
        if (mem.endsWith(u8, version, "-dev")) {
            const git_describe_output = std.ChildProcess.run(.{
                .allocator = b.allocator,
                .argv = &.{ "git", "-C", b.build_root.path orelse ".", "describe", "--long" },
            }) catch break :blk version;

            switch (git_describe_output.term) {
                .Exited => |status| if (status != 0) break :blk version,
                else => break :blk version,
            }

            var tokens = mem.split(u8, mem.trim(u8, git_describe_output.stdout, whitespace), "-");
            _ = tokens.next();
            const commit_count = tokens.next().?;
            const short_hash = tokens.next().?;
            std.debug.assert(tokens.next() == null);
            std.debug.assert(short_hash[0] == 'g');

            break :blk b.fmt(version ++ ".{s}+{s}", .{ commit_count, short_hash[1..] });
        } else {
            break :blk version;
        }
    };

    const git_rev = blk: {
        const nixos_rev_var = posix.getenv("_NIXOS_GIT_REV") orelse "unknown";
        const git_rev_parse_output = std.ChildProcess.run(.{
            .allocator = b.allocator,
            .argv = &.{ "git", "rev-parse", "HEAD" },
        }) catch break :blk nixos_rev_var;

        switch (git_rev_parse_output.term) {
            .Exited => |status| if (status != 0) break :blk nixos_rev_var,
            else => break :blk nixos_rev_var,
        }

        break :blk mem.trim(u8, git_rev_parse_output.stdout, whitespace);
    };

    const options = b.addOptions();
    // Flake-specific features are enabled by default.
    const flake = b.option(bool, "flake", "Use flake-specific commands and options") orelse true;
    // Change the nixpkgs branch to initialize configurations with
    const nixpkgs_version = b.option([]const u8, "nixpkgs-version", "Nixpkgs branch name to initialize configurations with") orelse "release-23.11";

    options.addOption([]const u8, "version", full_version);
    options.addOption(bool, "flake", flake);
    options.addOption([]const u8, "nixpkgs_version", nixpkgs_version);
    options.addOption([]const u8, "git_rev", git_rev);
    exe.root_module.addOptions("options", options);

    // Link to the Nix C API directly.
    exe.linkLibC();
    exe.linkLibrary(zignix_package.artifact("zignix"));
    exe.linkSystemLibrary("nixexprc");
    exe.linkSystemLibrary("nixstorec");
    exe.linkSystemLibrary("nixutilc");

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run.step);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

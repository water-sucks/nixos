const std = @import("std");
const os = std.os;
const mem = std.mem;

const whitespace = &std.ascii.whitespace;

/// While a `nixos` release is in development, this string should
/// contain the version in development with the "-dev" suffix.
/// When a release is tagged, the "-dev" suffix should be removed
/// for the commit that gets tagged. Directly after the tagged commit,
/// the version should be bumped and the "-dev" suffix added.
/// Thanks to `riverwm` for this idea for version number management.
const version = "0.5.0-dev";

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "nixos",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const full_version = blk: {
        if (mem.endsWith(u8, version, "-dev")) {
            var ret: u8 = undefined;
            const git_describe_output = b.execAllowFail(&.{ "git", "-C", b.build_root.path orelse ".", "describe", "--long" }, &ret, .Inherit) catch break :blk version;

            var tokens = mem.split(u8, mem.trim(u8, git_describe_output, whitespace), "-");
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
        var ret: u8 = undefined;
        const output = b.execAllowFail(&.{ "git", "rev-parse", "HEAD" }, &ret, .Inherit) catch {
            // This is for Nix derivation builds, this must be passed in Nix-side.
            break :blk os.getenv("_NIXOS_GIT_REV") orelse "unknown";
        };
        break :blk mem.trim(u8, output, whitespace);
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
    exe.addOptions("options", options);

    // Link to the Nix C API directly.
    exe.linkLibC();
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

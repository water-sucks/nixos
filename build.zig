const std = @import("std");
const posix = std.posix;
const mem = std.mem;
const Build = std.Build;
const ChildProcess = std.process.Child;
const OptimizeMode = std.builtin.OptimizeMode;

const assert = std.debug.assert;
const whitespace = std.ascii.whitespace;

/// While a `nixos` release is in development, this string should
/// contain the version in development with the "-dev" suffix.
/// When a release is tagged, the "-dev" suffix should be removed
/// for the commit that gets tagged. Directly after the tagged commit,
/// the version should be bumped and the "-dev" suffix added.
/// Thanks to `riverwm` for this idea for version number management.
const version = "0.10.0-dev";

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const full_version = getFullVersion(b);
    const git_rev = getGitRev(b);

    const options = b.addOptions();
    // Flake-specific features are enabled by default.
    const flake = b.option(bool, "flake", "Use flake-specific commands and options") orelse true;
    // Change the nixpkgs branch to initialize configurations with
    const nixpkgs_version = b.option([]const u8, "nixpkgs-version", "Nixpkgs branch name to initialize configurations with") orelse "24.05";

    options.addOption([]const u8, "version", full_version);
    options.addOption(bool, "flake", flake);
    options.addOption([]const u8, "nixpkgs_version", nixpkgs_version);
    options.addOption([]const u8, "git_rev", git_rev);

    const exe = nixosExecutable(b, .{
        .target = target,
        .optimize = optimize,
        .options = options,
    });
    b.installArtifact(exe);

    const exe_check = nixosExecutable(b, .{
        .target = target,
        .optimize = optimize,
        .options = options,
    });
    const check = b.step("check", "Check if executable compiles");
    check.dependOn(&exe_check.step);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run.step);

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

fn nixosExecutable(b: *Build, opts: struct {
    target: Build.ResolvedTarget,
    optimize: OptimizeMode,
    options: *Build.Step.Options,
}) *Build.Step.Compile {
    // const zignix_package = b.dependency("zignix", .{
    //     .target = opts.target,
    //     .optimize = opts.optimize,
    // });

    const common_dep_options = .{
        .target = opts.target,
        .optimize = opts.optimize,
    };

    const toml_package = b.dependency("zig-toml", common_dep_options);
    const zf_package = b.dependency("zf", common_dep_options);
    const zeit_package = b.dependency("zeit", common_dep_options);

    const exe = b.addExecutable(.{
        .name = "nixos",
        .root_source_file = b.path("src/main.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });
    // exe.root_module.addImport("nix", zignix_package.module("zignix"));
    exe.root_module.addImport("toml", toml_package.module("zig-toml"));
    exe.root_module.addImport("zf", zf_package.module("zf"));
    exe.root_module.addImport("zeit", zeit_package.module("zeit"));

    exe.root_module.addOptions("options", opts.options);

    // Link to the Nix C API directly.
    // exe.linkLibC();
    // exe.linkLibrary(zignix_package.artifact("zignix"));
    // exe.linkSystemLibrary("nixexprc");
    // exe.linkSystemLibrary("nixstorec");
    // exe.linkSystemLibrary("nixutilc");

    return exe;
}

fn getFullVersion(b: *Build) []const u8 {
    if (!mem.endsWith(u8, version, "-dev")) {
        return version;
    }

    const git_describe_output = ChildProcess.run(.{
        .allocator = b.allocator,
        .argv = &.{ "git", "-C", b.build_root.path orelse ".", "describe", "--long" },
    }) catch return version;

    switch (git_describe_output.term) {
        .Exited => |status| if (status != 0) return version,
        else => return version,
    }

    var tokens = mem.split(u8, mem.trim(u8, git_describe_output.stdout, &whitespace), "-");
    _ = tokens.next();
    const commit_count = tokens.next().?;
    const short_hash = tokens.next().?;
    assert(tokens.next() == null);
    assert(short_hash[0] == 'g');

    return b.fmt(version ++ ".{s}+{s}", .{ commit_count, short_hash[1..] });
}

fn getGitRev(b: *Build) []const u8 {
    const nixos_rev_var = posix.getenv("_NIXOS_GIT_REV") orelse "unknown";
    const git_rev_parse_output = ChildProcess.run(.{
        .allocator = b.allocator,
        .argv = &.{ "git", "rev-parse", "HEAD" },
    }) catch return nixos_rev_var;

    switch (git_rev_parse_output.term) {
        .Exited => |status| if (status != 0) return nixos_rev_var,
        else => return nixos_rev_var,
    }

    return mem.trim(u8, git_rev_parse_output.stdout, &whitespace);
}

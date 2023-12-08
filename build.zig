const std = @import("std");

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

    const shared_opts = b.addOptions();
    // Flake-specific features are enabled by default.
    const flake = b.option(bool, "flake", "Enable flake-specific commands and options") orelse true;
    // Change the nixpkgs branch to initialize configurations with
    const nixpkgs_version = b.option([]const u8, "nixpkgs-version", "Nixpkgs branch name to initialize configurations with") orelse "release-23.11";

    shared_opts.addOption(bool, "flake", flake);
    shared_opts.addOption([]const u8, "nixpkgs_version", nixpkgs_version);
    exe.addOptions("options", shared_opts);

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

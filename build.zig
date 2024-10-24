const std = @import("std");

pub fn build(b: *std.Build) void {
    const use_bundled = b.option(bool, "use_bundled", "Use the bundled SQLite") orelse false;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = b.addModule("s3db", .{
        .root_source_file = b.path("src/s3db.zig"),
    });
    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
        .use_bundled = use_bundled,
    });
    const lib = b.addStaticLibrary(.{
        .name = "s3db.zig",
        .root_source_file = b.path("src/s3db.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("sqlite", sqlite.module("sqlite"));
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/s3db.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("sqlite", sqlite.module("sqlite"));
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

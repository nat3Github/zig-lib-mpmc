const std = @import("std");
const builtin = @import("builtin");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Test the test application");

    const cmodule = b.addModule("mpmc", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    cmodule.link_libc = true;
    cmodule.addIncludePath(b.path("lfqueue/"));
    const flags = if (builtin.cpu.arch.isX86()) &.{"-mcx16"} else &.{};
    cmodule.addCSourceFiles(.{
        .files = &.{
            "lfqueue/wrapper/wqc.c",
            "lfqueue/wrapper/sqc.c",
            // "lfqueue/wfring_cas2.c",
        },
        .flags = flags,
    });

    const test1_compile = b.addTest(.{
        .root_module = cmodule,
        .target = target,
        .optimize = optimize,
    });
    const test1_run = b.addRunArtifact(test1_compile);
    test_step.dependOn(&test1_run.step);
}

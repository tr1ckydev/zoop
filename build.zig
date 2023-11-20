const std = @import("std");

pub fn build(b: *std.Build) void {
    const cham_dep = b.dependency("chameleon", .{});
    const cham_mod = cham_dep.module("chameleon");

    const zoop_mod = b.addModule("zoop", .{
        .source_file = .{ .path = "src/benchmark.zig" },
        .dependencies = &.{
            .{ .name = "chameleon", .module = cham_mod },
        },
    });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "zoop",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("chameleon", cham_mod);
    exe.addModule("zoop", zoop_mod);
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);
}

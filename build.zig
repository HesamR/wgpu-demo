const std = @import("std");

const wgpu = @import("wgpu");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const meshopt_mod = b.dependency("meshoptimizer", .{
        .target = target,
        .optimize = optimize,
    }).module("main");

    const tracy_mod = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
    }).module("main");

    const nuklear_mod = b.dependency("nuklear", .{
        .target = target,
        .optimize = optimize,
    }).module("main");

    const obj_mod = b.dependency("obj", .{
        .target = target,
        .optimize = optimize,
    }).module("obj");

    const sdl_mod = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
    }).module("main");

    const wgpu_dep = b.dependency("wgpu", .{
        .target = target,
        .optimize = optimize,
    });
    wgpu.installBinFiles(b, wgpu_dep, target);
    const wgpu_mod = wgpu_dep.module("main");

    const exe = b.addExecutable(.{
        .name = "wgpu-demo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("meshoptimizer", meshopt_mod);
    exe.root_module.addImport("nuklear", nuklear_mod);
    exe.root_module.addImport("tracy", tracy_mod);
    exe.root_module.addImport("obj", obj_mod);
    exe.root_module.addImport("sdl", sdl_mod);
    exe.root_module.addImport("wgpu", wgpu_mod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

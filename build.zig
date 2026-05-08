const std = @import("std");
const builtin = @import("builtin");

const min_zig_version = std.SemanticVersion{ .major = 0, .minor = 16, .patch = 0 };

pub fn build(b: *std.Build) void {
    if (builtin.zig_version.order(min_zig_version) == .lt) {
        std.log.err("ZigReflect requires Zig {f} or newer; found Zig {f}", .{
            min_zig_version,
            builtin.zig_version,
        });
        std.process.exit(1);
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ZigReflect",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
        .openssl = false, // set to true to enable TLS support
    });

    exe.root_module.addImport("zap", zap.module("zap"));

    const pg = b.dependency("datetime", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("datetime", pg.module("datetime"));

    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("sqlite", sqlite.module("sqlite"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

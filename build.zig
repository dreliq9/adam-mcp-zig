const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("adam_mcp_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // CLI executable: `adam-mcp` — scaffolds and audits MCP projects.
    const cli_exe = b.addExecutable(.{
        .name = "adam-mcp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adam_mcp_zig", .module = mod },
            },
        }),
    });
    b.installArtifact(cli_exe);

    const run_cli = b.addRunArtifact(cli_exe);
    if (b.args) |args| run_cli.addArgs(args);
    const run_step = b.step("cli", "Run the adam-mcp CLI (pass args after --)");
    run_step.dependOn(&run_cli.step);

    // Reference MCP: adam-greet-zig — built as a sub-target. Exercises
    // every SDK feature; doubles as the byte-equivalence target against
    // Python's adam-greet.
    const greet_exe = b.addExecutable(.{
        .name = "adam-greet-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("reference-mcp/adam-greet-zig/src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adam_mcp_zig", .module = mod },
            },
        }),
    });
    b.installArtifact(greet_exe);

    // Tests.
    const test_step = b.step("test", "Run library tests");
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);

    const cli_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adam_mcp_zig", .module = mod },
            },
        }),
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);
    test_step.dependOn(&run_cli_tests.step);
}

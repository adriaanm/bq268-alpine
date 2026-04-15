//! Build umbrella for the Zig-ported BQ268 tools.
//!
//! Cross-compiles a small set of standalone CLIs to arm-linux-musleabihf
//! (Cortex-A7) and installs each binary directly into tools/ so it
//! drops into the same place gcc used to put it. Invoked from the
//! repo justfile via `just build-tools`.

const std = @import("std");

const Tool = struct {
    name: []const u8,
    src: []const u8,
};

const tools = [_]Tool{
    .{ .name = "reboot-bootloader", .src = "src/reboot-bootloader.zig" },
    .{ .name = "rmt_storage", .src = "src/rmt_storage.zig" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    for (tools) |tool| {
        const mod = b.createModule(.{
            .root_source_file = b.path(tool.src),
            .target = target,
            .optimize = optimize,
        });
        const exe = b.addExecutable(.{
            .name = tool.name,
            .root_module = mod,
        });
        // Install directly into tools/ (the parent of zig-out), matching the
        // gcc convention — `cd tools && zig build --prefix .` puts the
        // binary at tools/<name>.
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "" } },
        });
        b.getInstallStep().dependOn(&install.step);
    }
}

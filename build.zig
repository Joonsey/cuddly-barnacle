const std = @import("std");

fn compress_file(builder: *std.Build, input_path: []const u8, output_path: []const u8) *std.Build.Step.Run {
    return builder.addSystemCommand(&.{
        "zstd", "-f", "-o", output_path, input_path,
    });
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library
    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const editor_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/editor.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mm_mod = b.createModule(.{
        .root_source_file = b.path("src/matchmaker.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "game",
        .root_module = exe_mod,
    });

    const editor = b.addExecutable(.{
        .name = "editor",
        .root_module = editor_exe_mod,
    });

    const matchmaker = b.addExecutable(.{
        .name = "matchmaker",
        .root_module = mm_mod,
    });

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    const udptp_lib = b.dependency("udptp", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("udptp", udptp_lib.module("udptp"));

    editor.linkLibrary(raylib_artifact);
    editor.root_module.addImport("raylib", raylib);
    editor.root_module.addImport("raygui", raygui);

    matchmaker.linkLibrary(raylib_artifact);
    matchmaker.root_module.addImport("raylib", raylib);
    matchmaker.root_module.addImport("raygui", raygui);

    matchmaker.root_module.addImport("udptp", udptp_lib.module("udptp"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);
    b.installArtifact(editor);
    b.installArtifact(matchmaker);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);
    const editor_cmd = b.addRunArtifact(editor);
    const matchmaker_cmd = b.addRunArtifact(matchmaker);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());
    editor_cmd.step.dependOn(b.getInstallStep());
    matchmaker_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
        editor_cmd.addArgs(args);
        matchmaker_cmd.addArgs(args);
    }

    const allocator = b.allocator;

    const assets_path = "compressed_assets";
    var asset_dir = try std.fs.cwd().openDir(assets_path, .{ .iterate = true });
    defer asset_dir.close();

    const compressed_path = "compressed_assets";
    var compressed_dir = try std.fs.cwd().openDir(compressed_path, .{ .iterate = true });
    defer compressed_dir.close();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const editor_step = b.step("editor", "Run the editor");
    editor_step.dependOn(&editor_cmd.step);

    var walker = try asset_dir.walk(allocator);
    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const input_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ assets_path, entry.path });
            const output_path = try std.fmt.allocPrint(allocator, "{s}/{s}.zst", .{ compressed_path, entry.path });
            const compress_step = compress_file(b, input_path, output_path);
            run_cmd.step.dependOn(&compress_step.step);
        }
        if (entry.kind == .directory) {
            _ = compressed_dir.makeDir(entry.path) catch null;
        }
    }

    exe.addIncludePath(.{ .cwd_relative = compressed_path });

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".

    const matchmaker_step = b.step("matchmaker", "Run the matchmaking server");
    matchmaker_step.dependOn(&matchmaker_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const editor_exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const mm_unit_tests = b.addTest(.{
        .root_module = mm_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const editor_run_exe_unit_tests = b.addRunArtifact(editor_exe_unit_tests);
    const mm_exe_unit_tests = b.addRunArtifact(mm_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&editor_run_exe_unit_tests.step);
    test_step.dependOn(&mm_exe_unit_tests.step);
}

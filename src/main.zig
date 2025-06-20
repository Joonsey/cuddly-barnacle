const std = @import("std");
const rl = @import("raylib");

const renderer = @import("renderer.zig");
const entity = @import("entity.zig");
const Level = @import("level.zig").Level;
const Levels = @import("level.zig").Levels;

const prefab = @import("prefabs.zig");

var WINDOW_WIDTH: i32 = 1600;
var WINDOW_HEIGHT: i32 = 900;
const RENDER_WIDTH: i32 = 720;
const RENDER_HEIGHT: i32 = 480;

pub fn main() !void {
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "test");
    var DBA = std.heap.DebugAllocator(.{}){};
    defer switch (DBA.deinit()) {
        .leak => {
            std.log.err("memory leaks detected!", .{});
        },
        .ok => {},
    };
    const allocator = DBA.allocator();
    var ecs: entity.ECS = .init(allocator);
    defer ecs.deinit();

    try prefab.init(allocator);
    defer prefab.deinit(allocator);

    var level: Level = try .init(Levels.level_one, allocator);
    defer level.deinit(allocator);
    level.load_ecs(&ecs);

    var tank = prefab.get(.tank);
    for (0..11) |i| {
        tank.transform.?.position = level.finish.get_spawn(i);
        tank.kinetic = .{ .rotation = level.finish.get_direction(), .velocity = .{ .x = 0, .y = 0 }};
        _ = ecs.spawn(tank);
    }

    tank.transform.?.position = level.finish.get_spawn(11);
    tank.kinetic = .{ .rotation = level.finish.get_direction(), .velocity = .{ .x = 0, .y = 0 }};
    tank.controller = .{};
    tank.race_context = .{};
    const player_id = ecs.spawn(tank);

    const scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT);
    var camera = renderer.Camera.init(RENDER_WIDTH, RENDER_HEIGHT);

    const shader = try rl.loadShader(
        null,
        "assets/shaders/world.fs",
    );

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        const deltatime = rl.getFrameTime();
        ecs.update(deltatime, level);
        var player = ecs.get_mut(player_id);
        const transform = &player.transform.?;
        var kinetics = &player.kinetic.?;
        const traction = level.get_traction(transform.position);
        kinetics.speed_multiplier = traction.speed_multiplier();
        kinetics.friction = traction.friction();
        camera.target(transform.position);
        const delta = kinetics.rotation + std.math.pi * 0.5 - camera.rotation;
        camera.rotation += delta / 12;

        level.update_intermediate_texture(camera);
        scene.begin();
        rl.clearBackground(.black);
        level.draw(shader, camera);
        ecs.draw(camera);

        const race_context = player.race_context.?;
        rl.drawText(rl.textFormat("%d/3", .{race_context.lap + 1}), 0, 16, 20, .white);
        scene.end();

        // drawing scene at desired resolution
        rl.beginDrawing();
        rl.drawTexturePro(scene.texture, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(RENDER_WIDTH),
            .height = @floatFromInt(-RENDER_HEIGHT),
        }, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(WINDOW_WIDTH),
            .height = @floatFromInt(WINDOW_HEIGHT),
        }, rl.Vector2.zero(), 0, .white);
        rl.drawFPS(0, 0);
        rl.endDrawing();
    }
}

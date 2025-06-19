const std = @import("std");
const rl = @import("raylib");

const renderer = @import("renderer.zig");
const entity = @import("entity.zig");
const Level = @import("level.zig").Level;
const Levels = @import("level.zig").Levels;

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

    var tank = try renderer.Stacked.init("assets/tank.png");

    const level: Level = try .init(Levels.level_one, allocator);
    defer level.deinit(allocator);
    level.load_ecs(&ecs);
    const player_id = ecs.spawn(.{
        .archetype = .Car,
        .controller = .{},
        .renderable = .{ .Stacked = tank.copy() },
        .collision = .{ .x = 0, .y = 0, .width = 18, .height = 18 },
        .kinetic = .{ .position = .{ .x = 100, .y = 100 }, .rotation = 0, .velocity = .{ .x = 0, .y = 0 },
        }
    });

    _ = ecs.spawn(.{
        .archetype = .Car,
        .renderable = .{ .Stacked = tank.copy() },
        .collision = .{ .x = 0, .y = 0, .width = 18, .height = 18 },
        .kinetic = .{ .position = .{ .x = 140, .y = 140 }, .rotation = 0, .velocity = .{ .x = 0, .y = 0 },
        }
    });

    const scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT);
    var camera = renderer.Camera.init(RENDER_WIDTH, RENDER_HEIGHT);

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        const deltatime = rl.getFrameTime();
        ecs.update(deltatime);
        var player = ecs.get_mut(player_id);
        var player_kinetics = &player.kinetic.?;
        const traction = level.get_traction(player_kinetics.position);
        player_kinetics.speed_multiplier = traction.speed_multiplier();
        player_kinetics.friction = traction.friction();
        camera.target(player_kinetics.position);
        const delta = player_kinetics.rotation + std.math.pi * 0.5 - camera.rotation;
        camera.rotation += delta / 12;

        scene.begin();
        rl.clearBackground(.black);
        level.draw(camera);
        ecs.draw(camera);
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

const std = @import("std");
const rl = @import("raylib");

const renderer = @import("renderer.zig");
const entity = @import("entity.zig");
const Level = @import("level.zig").Level;
const Levels = @import("level.zig").Levels;
const util = @import("util.zig");

var WINDOW_WIDTH: f32 = 1600;
var WINDOW_HEIGHT: f32 = 900;
const RENDER_WIDTH: f32 = 720;
const RENDER_HEIGHT: f32 = 480;


fn handle_input(camera: *renderer.Camera) void {
    const forward: rl.Vector2 = .{
        .x = @cos(camera.rotation),
        .y = @sin(camera.rotation),
    };

    const right: rl.Vector2 = .{
        .x = @cos(camera.rotation + std.math.pi * 0.5),
        .y = @sin(camera.rotation + std.math.pi * 0.5),
    };

    const accel = 15;
    var position = camera.position;
    if (rl.isKeyDown(.d)) {
        position.x += accel * forward.x;
        position.y += accel * forward.y;
    }
    if (rl.isKeyDown(.a)) {
        position.x -= accel * forward.x;
        position.y -= accel * forward.y;
    }
    if (rl.isKeyDown(.s)) {
        position.x += accel * right.x;
        position.y += accel * right.y;
    }
    if (rl.isKeyDown(.w)) {
        position.x -= accel * right.x;
        position.y -= accel * right.y;
    }

    if (rl.isKeyDown(.q)) {
        camera.rotation -= 0.1;
    }
    if (rl.isKeyDown(.e)) {
        camera.rotation += 0.1;
    }

    camera.target(position);
}

pub fn main() !void {
    rl.initWindow(@intFromFloat(WINDOW_WIDTH), @intFromFloat(WINDOW_HEIGHT), "test");
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

    var add_stack: std.ArrayListUnmanaged(entity.EntityId) = .{};
    defer add_stack.deinit(allocator);

    const cube_asset = try renderer.Stacked.init("assets/cube.png");
    const cube_id = ecs.spawn(.{
        .archetype = .Wall,
        .renderable = .{ .Stacked = cube_asset },
        .collision = .{ .x = 0 , .y = 0, .width = 40, .height = 40 },
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
    });

    var level: Level = try .init(Levels.level_one, allocator);
    defer level.deinit(allocator);
    level.load_ecs(&ecs);

    const scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT);
    var camera = renderer.Camera.init(RENDER_WIDTH, RENDER_HEIGHT);

    const shader = try rl.loadShader(
        null,
        "assets/shaders/world.fs",
    );

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        const deltatime = rl.getFrameTime();
        const cursor_pos = util.get_mouse_pos(RENDER_WIDTH, WINDOW_WIDTH, RENDER_HEIGHT, WINDOW_HEIGHT);
        var cube = ecs.get_mut(cube_id);

        cube.transform.?.position = camera.get_absolute_position(cursor_pos);
        if (cube.collision) |*collision| {
            const pos =  cube.transform.?.position;
            collision.x = pos.x - collision.width / 2;
            collision.y = pos.y - collision.height / 2;
        }

        if (rl.isMouseButtonPressed(.left)) {
            const id = ecs.spawn(.{
                .archetype = cube.archetype,
                .collision = cube.collision,
                .controller = cube.controller,
                .kinetic = cube.kinetic,
                .renderable = cube.renderable,
                .transform = cube.transform,
            });
            try add_stack.append(allocator, id);
        }

        if (rl.isKeyPressed(.z) and (rl.isKeyDown(.left_control))) if (add_stack.pop()) |id| ecs.despawn(id);
        if (rl.isKeyPressed(.r) and (rl.isKeyDown(.left_control))) {
            try level.save(ecs.entities.items, allocator, Levels.level_one);
            std.log.debug("SVAED!", .{});
        }

        ecs.update(deltatime);
        handle_input(&camera);

        level.update_intermediate_texture(camera);
        scene.begin();
        rl.clearBackground(.black);
        level.draw(shader, camera);
        ecs.draw(camera);
        scene.end();

        // drawing scene at desired resolution
        rl.beginDrawing();
        rl.drawTexturePro(scene.texture, .{
            .x = 0,
            .y = 0,
            .width = RENDER_WIDTH,
            .height = -RENDER_HEIGHT,
        }, .{
            .x = 0,
            .y = 0,
            .width = WINDOW_WIDTH,
            .height = WINDOW_HEIGHT,
        }, rl.Vector2.zero(), 0, .white);
        rl.drawFPS(0, 0);
        rl.endDrawing();
    }
}

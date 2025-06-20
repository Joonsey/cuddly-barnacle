const std = @import("std");
const rl = @import("raylib");

const renderer = @import("renderer.zig");
const entity = @import("entity.zig");
const Level = @import("level.zig").Level;
const Levels = @import("level.zig").Levels;
const Checkpoint = @import("level.zig").Checkpoint;
const Finish = @import("level.zig").Finish;
const util = @import("util.zig");

const prefab = @import("prefabs.zig");

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

    const accel = 70;
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

const Selected = union(enum) {
    None: void,
    Entity: entity.Entity,
    Checkpoints: struct {
        points: std.ArrayListUnmanaged(Checkpoint),
        current: usize = 0,
    },
    Finish: Finish,

    const Self = @This();
    fn draw_text(self: Self) void {
        const text = switch (self) {
            .Entity => "Entity",
            .Checkpoints => "Checkpoints",
            .Finish => "Finish",
            .None => "",
        };
        rl.drawText(text, 0, 16, 20, .white);
    }
    pub fn draw(self: Self, camera: renderer.Camera) void {
        draw_text(self);
        switch (self) {
            .Entity => |e| e.draw(camera),
            .Checkpoints => |c| {
                for (c.points.items, 0..) |point, i| {
                    const relative_pos = camera.get_relative_position(point.position);
                    rl.drawCircleV(relative_pos, point.radius, .{ .r = 255, .b = 0, .g = 0, .a = 100 });

                    if (i != 0) {
                        const previous_point = c.points.items[i - 1];
                        const previous_relative_pos = camera.get_relative_position(previous_point.position);
                        rl.drawLineV(previous_relative_pos, relative_pos, .black);
                    }
                }

                if (c.points.items.len > 0 and c.points.items.len > c.current) {
                    const current = c.points.items[c.current];
                    const relative_pos = camera.get_relative_position(current.position);
                    rl.drawCircleV(relative_pos, current.radius, .{ .r = 0, .b = 0, .g = 255, .a = 100 });
                }
        },
            .Finish => |f| {
                const left = camera.get_relative_position(f.left);
                const right = camera.get_relative_position(f.right);
                rl.drawLineV(left, right, .blue);
                rl.drawText("left", @intFromFloat(left.x), @intFromFloat(left.y), 10, .white);
                rl.drawText("right", @intFromFloat(right.x), @intFromFloat(right.y), 10, .white);

                for (0..12) |i| {
                    const spawn = f.get_spawn(i);
                    const rel_spawn = camera.get_relative_position(spawn);

                    const f_i: f32 = @floatFromInt(i);

                    var color: rl.Color = .purple;
                    color.r = @intFromFloat(f_i / 12 * 255);
                    rl.drawCircleV(rel_spawn, 9, color);
                }
        },
            .None => {},
        }
    }

    pub fn update(self: *Self, camera: renderer.Camera, cursor_pos: rl.Vector2, state: *State) void {
        const abs_position = camera.get_absolute_position(cursor_pos);
        switch (self.*) {
            .Entity => |*e| {
                e.transform = .{ .position = abs_position };

                if (rl.isMouseButtonPressed(.left)) {
                    const id = state.ecs.spawn(e.*);
                    state.add_stack.append(state.allocator, id) catch unreachable;
                }

                if (rl.isKeyPressed(.z)) {
                    const prev = state.iterator.previous();
                    e.collision = prev.collision;
                    e.renderable = prev.renderable;
                    e.archetype = prev.archetype;
                    e.shadow = prev.shadow;
                    e.prefab = prev.prefab;
                }

                if (rl.isKeyPressed(.x)) {
                    const next = state.iterator.next();
                    e.collision = next.collision;
                    e.renderable = next.renderable;
                    e.archetype = next.archetype;
                    e.shadow = next.shadow;
                    e.prefab = next.prefab;
                }
            },
            .Checkpoints => |*c| {
                if (c.current < c.points.items.len) {
                    const current_cp = &c.points.items[c.current];

                    current_cp.position = abs_position;
                    if (rl.isMouseButtonPressed(.left)) {
                        c.current = c.points.items.len;
                    }

                    current_cp.radius += rl.getMouseWheelMove() * 5;
                    state.radius = current_cp.radius;

                } else {
                    const new_cp = Checkpoint{ .position = abs_position, .radius = state.radius };

                    if (rl.isMouseButtonPressed(.left)) {
                        c.current += 1;
                        c.points.append(state.allocator, new_cp) catch unreachable;
                    }
                }
                if (rl.isKeyPressed(.x)) {
                    c.current = inc(c.current, 1, c.points.items.len);
                }
                if (rl.isKeyPressed(.z)) {
                    c.current = inc(c.current, -1, c.points.items.len);
                }
        },
            .Finish => |*f| {
                if (rl.isMouseButtonPressed(.left)) {
                    f.left = abs_position;
                } else if (rl.isMouseButtonPressed(.right)) {
                    f.right = abs_position;
                }

                state.level.finish = f.*;
        },
            .None => {},
        }
    }
};

fn inc(current: usize, delta: i32, max: usize) usize {
    return @intCast(@mod((@as(i32, @intCast(current)) + delta), @as(i32, @intCast(max))));
}

const State = struct {
    allocator: std.mem.Allocator,
    add_stack: std.ArrayListUnmanaged(entity.EntityId),
    level: Level,
    ecs: entity.ECS,
    iterator: prefab.Iterator,

    radius: f32 = 64,
};

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

    try prefab.init(allocator);
    defer prefab.deinit(allocator);

    var selected: Selected = .{ .Entity = prefab.get(.cube) };

    var level: Level = try .init(Levels.level_one, allocator);
    defer level.deinit(allocator);
    level.load_ecs(&ecs);

    const scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT);
    var camera = renderer.Camera.init(RENDER_WIDTH, RENDER_HEIGHT);

    var checkpoints: std.ArrayListUnmanaged(Checkpoint) = .{};
    defer checkpoints.deinit(allocator);

    var state: State = .{
        .add_stack = add_stack,
        .allocator = allocator,
        .ecs = ecs,
        .level = level,
        .iterator = prefab.iter(allocator),
    };

    const shader = try rl.loadShader(
        null,
        "assets/shaders/world.fs",
    );

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        const deltatime = rl.getFrameTime();
        const cursor_pos = util.get_mouse_pos(RENDER_WIDTH, WINDOW_WIDTH, RENDER_HEIGHT, WINDOW_HEIGHT);

        selected.update(camera, cursor_pos, &state);

        if (rl.isKeyPressed(.z) and (rl.isKeyDown(.left_control))) if (add_stack.pop()) |id| state.ecs.despawn(id);
        if (rl.isKeyPressed(.r) and (rl.isKeyDown(.left_control))) {
            try level.save(state.ecs.entities.items, state.level.checkpoints, state.level.finish, allocator, Levels.level_one);
            std.log.debug("SVAED!", .{});
        }

        if (rl.isKeyPressed(.c)) {
            selected = .{ .Checkpoints = .{ .points = checkpoints } };
        }

        if (rl.isKeyPressed(.f)) {
            selected = .{ .Finish = state.level.finish };
        }


        state.ecs.update(deltatime);
        handle_input(&camera);

        level.update_intermediate_texture(camera);
        scene.begin();
        rl.clearBackground(.black);
        level.draw(shader, camera);
        state.ecs.draw(camera);
        selected.draw(camera);
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

const std = @import("std");
const rl = @import("raylib");

const renderer = @import("renderer.zig");
const entity = @import("entity.zig");
const level = @import("level.zig");
const Checkpoint = @import("level.zig").Checkpoint;
const Finish = @import("level.zig").Finish;
const util = @import("util.zig");
const Particles = @import("particles.zig").Particles;

const prefab = @import("prefabs.zig");
const shared = @import("shared.zig");

var WINDOW_WIDTH: f32 = 1600;
var WINDOW_HEIGHT: f32 = 900;
const RENDER_WIDTH = shared.RENDER_WIDTH;
const RENDER_HEIGHT = shared.RENDER_HEIGHT;

fn handle_input(camera: *renderer.Camera) void {
    const forward: rl.Vector2 = .{
        .x = @cos(camera.rotation),
        .y = @sin(camera.rotation),
    };

    const right: rl.Vector2 = .{
        .x = @cos(camera.rotation + std.math.pi * 0.5),
        .y = @sin(camera.rotation + std.math.pi * 0.5),
    };

    const accel = 10;
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
        camera.rotation -= 0.01;
    }
    if (rl.isKeyDown(.e)) {
        camera.rotation += 0.01;
    }

    camera.target(position);
}

const Selected = union(enum) {
    None: void,
    Entity: struct {
        e: entity.Entity,
        mouse_start: rl.Vector2,
        mouse_end: rl.Vector2,
        debug_color: rl.Color = .green,
    },
    Checkpoints: struct {
        points: std.ArrayListUnmanaged(Checkpoint),
        current: usize = 0,
    },
    Finish: Finish,

    const Self = @This();
    fn draw_text(self: Self) void {
        const text = switch (self) {
            .Entity => "Entity",
            .Checkpoints => |cp| rl.textFormat("Checkpoints: %d/%d", .{ cp.current, cp.points.items.len }),
            .Finish => "Finish",
            .None => "",
        };
        rl.drawText(text, 0, 16, 20, .white);
    }
    pub fn draw(self: Self, camera: renderer.Camera) void {
        draw_text(self);
        switch (self) {
            .Entity => |ent| {
                const e = ent.e;
                e.draw(camera);

                if (rl.isKeyDown(.left_shift)) {
                    const rel_position = camera.get_relative_position(e.transform.?.position);
                    rl.drawRectangleLines(@intFromFloat(rel_position.x), @intFromFloat(rel_position.y), 16, 16, ent.debug_color);
                }

                if (rl.isMouseButtonDown(.right)) {
                    rl.drawLineV(ent.mouse_start, ent.mouse_end, .white);
                }
            },
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

                for (1..13) |i| {
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
            .Entity => |*ent| {
                const e = &ent.e;
                e.transform = .{ .position = abs_position, .rotation = if (e.transform) |t| t.rotation else 0 };
                const mouse_wheel_move = rl.getMouseWheelMove() / 8;
                e.transform.?.rotation += mouse_wheel_move * std.math.pi;

                if (rl.isKeyDown(.left_alt)) {
                    for (state.ecs.entities.items) |other| {
                        if (other.transform) |transform| {
                            if (transform.position.distance(abs_position) <= 24) {
                                const delta_y: i32 = @intFromFloat(@abs(transform.position.y - abs_position.y));
                                const delta_x: i32 = @intFromFloat(@abs(transform.position.x - abs_position.x));
                                const y_aligned = delta_y < delta_x;
                                if (y_aligned) e.transform.?.position.y = transform.position.y else e.transform.?.position.x = transform.position.x;

                                const pixel_perfect = if (other.renderable) |renderable| switch (renderable) {
                                    .Flat => |f| if (y_aligned) f.texture.width - 1 == delta_x else f.texture.height - 1 == delta_y,
                                    .Stacked => |f| if (y_aligned) f.texture.width - 1 == delta_x else @divTrunc(f.texture.height, f.texture.width) == delta_y,
                                } else false;

                                ent.debug_color = if (pixel_perfect) .blue else .green;

                                if (pixel_perfect and rl.isMouseButtonDown(.left)) {
                                    if (state.add_stack.getLastOrNull()) |last| {
                                        if (last >= state.ecs.entities.items.len) {
                                            // something weird has happened, we ignore and proceed
                                            const id = state.ecs.spawn(e.*);
                                            state.add_stack.append(state.allocator, id) catch unreachable;
                                        } else {
                                            const last_transform = state.ecs.get(last).transform.?;
                                            const perfect_delta_x = @abs(last_transform.position.x - e.transform.?.position.x);
                                            const perfect_delta_y = @abs(last_transform.position.y - e.transform.?.position.y);
                                            if (perfect_delta_x < 1 and perfect_delta_y > 8 or perfect_delta_y < 1 and perfect_delta_x > 8) {
                                                const id = state.ecs.spawn(e.*);
                                                state.add_stack.append(state.allocator, id) catch unreachable;
                                            }
                                        }
                                    } else {
                                        const id = state.ecs.spawn(e.*);
                                        state.add_stack.append(state.allocator, id) catch unreachable;
                                    }
                                }
                                break;
                            }
                        }
                    }
                }

                if (rl.isMouseButtonPressed(.left)) {
                    const id = state.ecs.spawn(e.*);
                    state.add_stack.append(state.allocator, id) catch unreachable;
                }

                if (rl.isKeyPressed(.z) and !rl.isKeyDown(.left_control)) {
                    var prev = state.iterator.previous();
                    prev.transform = e.transform;
                    e.* = prev;
                }

                if (rl.isKeyPressed(.x) and !rl.isKeyDown(.left_control)) {
                    var next = state.iterator.next();
                    next.transform = e.transform;
                    e.* = next;
                }

                if (rl.isMouseButtonDown(.right)) {
                    for (state.ecs.entities.items, 0..) |potential_entity, id| {
                        if (potential_entity.transform) |transform| {
                            if (transform.position.distance(abs_position) < 16) {
                                state.ecs.despawn(@intCast(id));
                                e.* = potential_entity;

                                for (state.add_stack.items, 0..) |*add_id, idx| {
                                    if (add_id.* == id) {
                                        _ = state.add_stack.swapRemove(idx);
                                    }
                                    if (add_id.* < id) {
                                        add_id.* -= 1;
                                    }
                                }
                                break;
                            }
                        }
                    }
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

                state.level.checkpoints = c.points.items;

                if (rl.isKeyPressed(.x) and !rl.isKeyDown(.left_control)) {
                    c.current = inc(c.current, 1, c.points.items.len);
                }
                if (rl.isKeyPressed(.z) and !rl.isKeyDown(.left_control)) {
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
    level: level.Level,
    ecs: entity.ECS,
    iterator: prefab.Iterator,
    particles: *Particles,

    radius: f32 = 64,
};

fn draw_debug(ecs: entity.ECS, camera: renderer.Camera) void {
    for (ecs.entities.items) |e| {
        if (e.transform) |transform| {
            const rel_position = camera.get_relative_position(transform.position);
            rl.drawRectangleLines(@intFromFloat(rel_position.x), @intFromFloat(rel_position.y), 16, 16, .red);
        }
    }
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

    var add_stack: std.ArrayListUnmanaged(entity.EntityId) = .{};
    defer add_stack.deinit(allocator);

    try prefab.init(allocator);
    defer prefab.deinit(allocator);

    try level.init(allocator);
    defer level.deinit(allocator);

    const particles = try allocator.create(Particles);
    particles.* = .init(allocator);
    defer allocator.destroy(particles);
    defer particles.deinit();

    var selected: Selected = .{ .Entity = .{ .e = prefab.get(.cube), .mouse_end = .init(0, 0), .mouse_start = .init(0, 0) } };

    var ecs: entity.ECS = .init(allocator);

    var lvl = level.get(1);
    lvl.load_ecs(&ecs);

    const scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT);
    var camera = renderer.Camera.init(RENDER_WIDTH, RENDER_HEIGHT);
    camera.screen_offset.x = RENDER_WIDTH / 2;
    camera.screen_offset.y = RENDER_HEIGHT / 2;

    var checkpoints: std.ArrayListUnmanaged(Checkpoint) = .{};
    defer checkpoints.deinit(allocator);
    try checkpoints.appendSlice(allocator, lvl.checkpoints);

    var state: State = .{
        .add_stack = add_stack,
        .allocator = allocator,
        .ecs = ecs,
        .particles = particles,
        .level = lvl,
        .iterator = prefab.iter(allocator),
    };

    defer state.ecs.deinit();

    rl.setTargetFPS(144);
    while (!rl.windowShouldClose()) {
        const deltatime = rl.getFrameTime();
        const cursor_pos = util.get_mouse_pos(RENDER_WIDTH, WINDOW_WIDTH, RENDER_HEIGHT, WINDOW_HEIGHT);

        selected.update(camera, cursor_pos, &state);

        if (rl.isKeyPressed(.z) and (rl.isKeyDown(.left_control))) if (state.add_stack.pop()) |id| state.ecs.despawn(id);
        if (rl.isKeyPressed(.r) and (rl.isKeyDown(.left_control))) {
            try lvl.save(state.ecs.entities.items, checkpoints.items, state.level.finish, allocator, level.Levels.level_two);
            std.log.debug("SAVED!", .{});
        }

        if (rl.isKeyPressed(.c)) {
            selected = .{ .Checkpoints = .{ .points = checkpoints, .current = checkpoints.items.len } };
        }

        if (rl.isKeyPressed(.f)) {
            selected = .{ .Finish = state.level.finish };
        }

        state.ecs.update(deltatime, state.level);
        state.particles.update(deltatime, &state.ecs);
        handle_input(&camera);

        state.level.update_intermediate_texture(camera);
        scene.begin();
        rl.clearBackground(.black);
        state.level.draw(camera);
        state.particles.draw(camera);
        state.ecs.draw(camera);
        if (rl.isKeyDown(.left_shift)) draw_debug(state.ecs, camera);
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

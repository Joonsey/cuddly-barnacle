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

const Tracks = struct {
    const Query = struct {
        entity: entity.EntityId,
        index: usize,
    };

    const Track = struct {
        position: rl.Vector2,
        rotation: f32 = 0,
    };

    tracks: std.AutoHashMapUnmanaged(Query, std.ArrayListUnmanaged(Track)) = .{},
    indexes: std.AutoHashMapUnmanaged(entity.EntityId, usize) = .{},

    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.tracks.valueIterator();
        while (iter.next()) |track| track.clearAndFree(self.allocator);
        self.tracks.clearAndFree(self.allocator);
        self.indexes.clearAndFree(self.allocator);
    }

    pub fn update(self: *Self, ecs: *entity.ECS) void {
        for (ecs.entities.items, 0..) |e, i| {
            if (e.drift) |drift| {
                if (e.transform) |transform| {
                    switch (drift.state) {
                        .charging => {
                            const index: usize = self.indexes.get(@intCast(i)) orelse blk: {
                                self.indexes.put(self.allocator, @intCast(i), 0) catch unreachable;
                                break :blk 0;
                            };
                            const query: Query = .{.index = index, .entity = @intCast(i)};
                            var tracks: std.ArrayListUnmanaged(Track) = self.tracks.get(query) orelse .{};
                            tracks.append(self.allocator, .{ .position = transform.position, .rotation = transform.rotation }) catch unreachable;
                            self.tracks.put(self.allocator, query, tracks) catch unreachable;
                        },
                        else => {
                            if (self.indexes.getPtr(@intCast(i))) |index| {
                                const query: Query = .{.index = index.*, .entity = @intCast(i)};
                                if (self.tracks.get(query)) |_| index.* += 1;
                            }
                        }
                    }
                }
            }
        }
    }

    pub fn draw(self: Self, camera: renderer.Camera) void {
        var iter = self.tracks.valueIterator();
        var left: std.ArrayListUnmanaged(rl.Vector2) = .{};
        var right: std.ArrayListUnmanaged(rl.Vector2) = .{};

        const car_radius = 7;
        while (iter.next()) |tracks| {
            for (tracks.items) |track| {
                const forward = rl.Vector2{ .x = @cos(track.rotation), .y = @sin(track.rotation) };
                const perp = rl.Vector2{ .x = -forward.y, .y = forward.x };


                left.append(self.allocator, camera.get_relative_position(track.position.add(perp.scale(car_radius)))) catch unreachable;
                right.append(self.allocator, camera.get_relative_position(track.position.subtract(perp.scale(car_radius)))) catch unreachable;

            }
            rl.drawLineStrip(left.items, .black);
            rl.drawLineStrip(right.items, .black);
            left.clearAndFree(self.allocator);
            right.clearAndFree(self.allocator);
        }
    }
};

const Particles = struct {
    const Spark = struct {
        scale: f32 = 1.0,
        force: f32 = 3.0,
        alt_color: rl.Color,
    };

    const ParticleType = union(enum) {
        Rectangle: rl.Vector2,
        Spark: Spark,
    };

    const Particle = struct {
        position: rl.Vector2,
        velocity: rl.Vector2 = .init(0, 0),
        rotation: f32 = 0,
        lifetime: f32,
        color: rl.Color,
        kind: ParticleType,
    };

    particles: std.ArrayListUnmanaged(Particle) = .{},

    allocator: std.mem.Allocator,
    passed_frames: u32 = 0,
    particle_index: u32 = 0,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self:* Self) void {
        self.particles.clearAndFree(self.allocator);
    }

    pub fn update(self: *Self, deltatime: f32, ecs: entity.ECS) void {
        self.passed_frames += 1;
        for (self.particles.items) |*particle| {
            particle.lifetime = @max(0, particle.lifetime - deltatime);
            particle.position = particle.position.add(particle.velocity.scale(deltatime));
        }

        const max = self.particles.items.len;
        var i: usize = 0;
        for (0..max) |_| {
            const particle = self.particles.items[i];
            if (particle.lifetime <= 0) {
                _ = self.particles.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        const interval = 2;
        if (self.passed_frames % interval != 0) return;

        self.particle_index += 1;
        const back_velocity = 5;
        const side_velocity = 12;
        for (ecs.entities.items) |e| {
            if (e.transform) |transform| {
                if (transform.height != 0) continue;
                const forward = rl.Vector2{ .x = @cos(transform.rotation), .y = @sin(transform.rotation) };
                const perp = rl.Vector2{ .x = -forward.y, .y = forward.x };

                const side = perp.scale(@sin(@as(f32, @floatFromInt(self.passed_frames))));
                const dir = side.scale(side_velocity).subtract(forward.scale(back_velocity));

                const pos = transform.position.add(side.scale(3));

                if (e.kinetic) |kinetic| {
                    const length = kinetic.velocity.length();
                    if (length == 0) continue;
                    if (self.particle_index % 4 == 0) {
                        self.particles.append(self.allocator, Particle{
                            .position = pos,
                            .velocity = dir.scale(0.7),
                            .lifetime = 1,
                            .color = .brown,
                            .kind = .{.Rectangle = .{ .x = 2, .y = 2 }},
                            .rotation = transform.rotation,
                        }) catch unreachable;
                    } else {
                        self.particles.append(self.allocator, Particle{
                            .position = pos,
                            .velocity = dir.scale(0.7),
                            .lifetime = 1,
                            .color = .dark_brown,
                            .kind = .{.Rectangle = .{ .x = 2, .y = 2 }},
                            .rotation = transform.rotation,
                        }) catch unreachable;
                    }
                }
                if (e.drift) |drift| {
                    switch (drift.state) {
                        .boosting => {
                            self.particles.append(self.allocator, Particle{
                                .position = pos.add(side.scale(2)),
                                .velocity = dir.scale(1),
                                .lifetime = 1,
                                .color = .yellow,
                                .kind = .{.Spark = .{ .scale = 5, .alt_color = .yellow, .force = 2 }},
                                .rotation = transform.rotation,
                            }) catch unreachable;
                            self.particles.append(self.allocator, Particle{
                                .position = pos.add(side),
                                .velocity = dir.scale(1),
                                .lifetime = 0.5,
                                .color = .orange,
                                .kind = .{.Spark = .{ .scale = 10, .alt_color = .orange, .force = 2 }},
                                .rotation = transform.rotation,
                            }) catch unreachable;
                            self.particles.append(self.allocator, Particle{
                                .position = transform.position,
                                .velocity = dir.scale(1),
                                .lifetime = 0.5,
                                .color = .yellow,
                                .kind = .{.Spark = .{ .scale = 8, .alt_color = .yellow, .force = 4 }},
                                .rotation = transform.rotation,
                            }) catch unreachable;
                            if (self.particle_index % 4 == 0) {
                                self.particles.append(self.allocator, Particle{
                                    .position = pos,
                                    .velocity = dir.scale(1.2),
                                    .lifetime = 1,
                                    .color = .red,
                                    .kind = .{.Spark = .{ .scale = 5, .alt_color = .red, .force = 4 }},
                                    .rotation = transform.rotation,
                                }) catch unreachable;
                            } else if (self.particle_index % 3 == 0) {
                                self.particles.append(self.allocator, Particle{
                                    .position = pos,
                                    .velocity = dir.scale(0.8),
                                    .lifetime = 0.8,
                                    .color = .orange,
                                    .kind = .{.Spark = .{ .scale = 5, .alt_color = .orange, .force = 2 }},
                                    .rotation = transform.rotation,
                                }) catch unreachable;
                            }
                        },
                        .charging => |time_held| {
                            const predicted_stage: entity.DriftState.BoostStage = .get_stage(time_held);
                            switch (predicted_stage) {
                                .none => {
                                    if (self.particle_index % 4 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(1.2),
                                            .lifetime = 1,
                                            .color = .white,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .white, .force = 4 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    } else if (self.particle_index % 3 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(0.8),
                                            .lifetime = 0.8,
                                            .color = .gray,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .gray, .force = 2 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    } else if (self.particle_index % 2 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(1),
                                            .lifetime = 1,
                                            .color = .light_gray,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .light_gray, .force = 2 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    }
                                },
                                .Mini => {
                                    if (self.particle_index % 4 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(1.2),
                                            .lifetime = 1,
                                            .color = .white,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .white, .force = 4 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    } else if (self.particle_index % 3 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(0.8),
                                            .lifetime = 0.8,
                                            .color = .gray,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .gray, .force = 2 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    } else if (self.particle_index % 2 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(1),
                                            .lifetime = 1,
                                            .color = .light_gray,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .light_gray, .force = 2 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    }
                                },
                                .Medium => {
                                    if (self.particle_index % 4 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(1.2),
                                            .lifetime = 1,
                                            .color = .white,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .white, .force = 4 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    } else if (self.particle_index % 3 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(0.8),
                                            .lifetime = 0.8,
                                            .color = .blue,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .blue, .force = 2 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    } else if (self.particle_index % 2 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(1),
                                            .lifetime = 1,
                                            .color = .sky_blue,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .sky_blue, .force = 2 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    }
                                },
                                .Turbo => {
                                    if (self.particle_index % 4 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(1.2),
                                            .lifetime = 1,
                                            .color = .dark_purple,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .dark_purple, .force = 4 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    } else if (self.particle_index % 3 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(0.8),
                                            .lifetime = 0.8,
                                            .color = .purple,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .purple, .force = 2 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    } else if (self.particle_index % 2 == 0) {
                                        self.particles.append(self.allocator, Particle{
                                            .position = pos,
                                            .velocity = dir.scale(1),
                                            .lifetime = 1,
                                            .color = .violet,
                                            .kind = .{.Spark = .{ .scale = 5, .alt_color = .violet, .force = 2 }},
                                            .rotation = transform.rotation,
                                        }) catch unreachable;
                                    }
                                },
                            }
                        },
                        .none => {},
                    }
                }
            }
        }
    }

    pub fn draw(self: Self, camera: renderer.Camera) void {
        for (self.particles.items) |particle| {
            if (camera.is_out_of_bounds(particle.position)) continue;
            const rel_position = camera.get_relative_position(particle.position);
            switch (particle.kind) {
                .Rectangle => |size| {
                    //rl.drawRectangleV(rel_position, size, particle.color);
                    rl.drawRectanglePro(.{ .x = rel_position.x, .y = rel_position.y, .width = size.x, .height = size.y }, .{ .x = size.x / 2, .y = size.y / 2 }, particle.rotation, particle.color);
                },
                .Spark => |spark| {
                    const lifetime_scaled = particle.lifetime * spark.scale;
                    const angle = particle.rotation;

                    const front: rl.Vector2 = .{
                        .x = particle.position.x + @cos(angle) * lifetime_scaled,
                        .y = particle.position.y + @sin(angle) * lifetime_scaled,
                    };

                    const side1: rl.Vector2 = .{
                        .x = particle.position.x + @cos(angle + std.math.pi / 2.0) * lifetime_scaled * 0.3,
                        .y = particle.position.y + @sin(angle + std.math.pi / 2.0) * lifetime_scaled * 0.3,
                    };

                    const back: rl.Vector2 = .{
                        .x = particle.position.x - @cos(angle) * lifetime_scaled * 3.5,
                        .y = particle.position.y - @sin(angle) * lifetime_scaled * 3.5,
                    };

                    const side2: rl.Vector2 = .{
                        .x = particle.position.x + @cos(angle - std.math.pi / 2.0) * lifetime_scaled * 0.3,
                        .y = particle.position.y + @sin(angle - std.math.pi / 2.0) * lifetime_scaled * 0.3,
                    };

                    const p1 = camera.get_relative_position(front);
                    const p2 = camera.get_relative_position(side1);
                    const p3 = camera.get_relative_position(back);
                    const p4 = camera.get_relative_position(side2);

                    rl.drawTriangle(p3, p2, p1, particle.color);
                    rl.drawTriangle(p4, p3, p1, spark.alt_color);
                }
            }
        }
    }
};

const Gamestate = struct {
    ecs: entity.ECS,
    level: Level,
    camera: renderer.Camera,
    tracks: Tracks,
    particles: Particles,

    allocator: std.mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, comptime lvl_path: []const u8) !Self {
        return .{
            .ecs = .init(allocator),
            .level = try .init(lvl_path, allocator),
            .camera = .init(RENDER_WIDTH, RENDER_HEIGHT),
            .tracks = try .init(allocator),
            .particles = .init(allocator),

            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.ecs.deinit();
        self.level.deinit(self.allocator);
        self.tracks.deinit();
        self.particles.deinit();
    }

    pub fn update(self: *Self, deltatime: f32) void {
        self.ecs.update(deltatime, self.level);
        self.level.update_intermediate_texture(self.camera);
        self.tracks.update(&self.ecs);
        self.particles.update(deltatime, self.ecs);
    }

    pub fn draw(self: Self) void {
        self.level.draw(self.camera);
        self.tracks.draw(self.camera);
        self.particles.draw(self.camera);
        self.ecs.draw(self.camera);
    }
};

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
    try prefab.init(allocator);
    defer prefab.deinit(allocator);

    var state: Gamestate = try .init(allocator, Levels.level_one);
    defer state.deinit();

    state.level.load_ecs(&state.ecs);

    var tank = prefab.get(.tank);
    tank.transform.?.position = state.level.finish.get_spawn(0);
    tank.transform.?.rotation = state.level.finish.get_direction();
    tank.kinetic = .{ .velocity = .{ .x = 0, .y = 0 }};
    tank.controller = .{};
    tank.drift = .{};
    tank.race_context = .{};
    const player_id = state.ecs.spawn(tank);

    const scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT);


    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        const deltatime = rl.getFrameTime();
        state.update(deltatime);

        var player = state.ecs.get_mut(player_id);
        const transform = &player.transform.?;
        var kinetics = &player.kinetic.?;
        const traction = state.level.get_traction(transform.position);

        kinetics.speed_multiplier = traction.speed_multiplier();
        kinetics.friction = traction.friction();

        state.camera.target(transform.position);
        const delta = transform.rotation + std.math.pi * 0.5 - state.camera.rotation;
        state.camera.rotation += delta / 24;


        scene.begin();
        rl.clearBackground(.black);
        state.draw();

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

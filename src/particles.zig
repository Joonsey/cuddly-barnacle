const std = @import("std");
const rl = @import("raylib");

const renderer = @import("renderer.zig");
const entity = @import("entity.zig");

pub const Particles = struct {
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

    pub fn deinit(self: *Self) void {
        self.particles.clearAndFree(self.allocator);
    }

    pub fn on_event(s: *anyopaque, ecs: *entity.ECS, event: entity.Event) void {
        const self: *Self = @alignCast(@ptrCast(s));
        switch (event) {
            .Collision => |col| {
                const a = ecs.get(col.a);
                const b = ecs.get(col.b);
                if (a.archetype == .ItemBox and b.archetype == .Car or b.archetype == .ItemBox and a.archetype == .Car) {
                    const pos = a.transform.?.position;
                    const num_angles = 16;
                    for (0..num_angles) |i| {
                        const f_i: f32 = @floatFromInt(i);
                        const f_num_angles: f32 = @floatFromInt(num_angles);
                        const angle = (f_i / f_num_angles) * std.math.pi * 2;

                        const x: f32 = @cos(angle);
                        const y: f32 = @sin(angle);

                        // IDK how i made this but it looks kinda cool???
                        const dir: rl.Vector2 = .{ .x = x, .y = y };
                        self.particles.append(self.allocator, Particle{
                            .position = pos,
                            .velocity = dir.scale(20),
                            .lifetime = 1,
                            .color = .violet,
                            .kind = .{ .Spark = .{ .scale = 5, .alt_color = .violet, .force = 7 } },
                            .rotation = -angle,
                        }) catch unreachable;

                        self.particles.append(self.allocator, Particle{
                            .position = pos,
                            .velocity = dir.scale(10),
                            .lifetime = 1.4,
                            .color = .dark_purple,
                            .kind = .{ .Spark = .{ .scale = 3, .alt_color = .dark_gray, .force = 4 } },
                            .rotation = -angle,
                        }) catch unreachable;
                    }
                }
            },
            else => {},
        }
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

        const interval = 4;
        if (self.passed_frames % interval != 0) return;

        self.particle_index += 1;
        const back_velocity = 5;
        const side_velocity = 12;
        for (ecs.entities.items) |e| {
            if (e.transform) |transform| {
                const forward = rl.Vector2{ .x = @cos(transform.rotation), .y = @sin(transform.rotation) };
                const perp = rl.Vector2{ .x = -forward.y, .y = forward.x };

                const side = perp.scale(@sin(@as(f32, @floatFromInt(self.passed_frames))));
                const dir = side.scale(side_velocity).subtract(forward.scale(back_velocity));

                const pos = transform.position.add(side.scale(3));
                if (e.boost) |boost| {
                    if (boost.boost_time > 0) {
                        self.particles.append(self.allocator, Particle{
                            .position = pos.add(side.scale(2)),
                            .velocity = dir.scale(1),
                            .lifetime = 1,
                            .color = .yellow,
                            .kind = .{ .Spark = .{ .scale = 10, .alt_color = .yellow, .force = 2 } },
                            .rotation = transform.rotation,
                        }) catch unreachable;
                        self.particles.append(self.allocator, Particle{
                            .position = pos.add(side),
                            .velocity = dir.scale(1),
                            .lifetime = 0.5,
                            .color = .orange,
                            .kind = .{ .Spark = .{ .scale = 10, .alt_color = .orange, .force = 2 } },
                            .rotation = transform.rotation,
                        }) catch unreachable;
                        self.particles.append(self.allocator, Particle{
                            .position = transform.position,
                            .velocity = dir.scale(1),
                            .lifetime = 0.5,
                            .color = .yellow,
                            .kind = .{ .Spark = .{ .scale = 8, .alt_color = .yellow, .force = 4 } },
                            .rotation = transform.rotation,
                        }) catch unreachable;
                        if (self.particle_index % 4 == 0) {
                            self.particles.append(self.allocator, Particle{
                                .position = pos,
                                .velocity = dir.scale(1.2),
                                .lifetime = 1,
                                .color = .red,
                                .kind = .{ .Spark = .{ .scale = 5, .alt_color = .red, .force = 4 } },
                                .rotation = transform.rotation,
                            }) catch unreachable;
                        } else if (self.particle_index % 3 == 0) {
                            self.particles.append(self.allocator, Particle{
                                .position = pos,
                                .velocity = dir.scale(0.8),
                                .lifetime = 0.8,
                                .color = .orange,
                                .kind = .{ .Spark = .{ .scale = 5, .alt_color = .orange, .force = 2 } },
                                .rotation = transform.rotation,
                            }) catch unreachable;
                        }
                    }
                }
                if (transform.height != 0) continue;

                if (e.kinetic) |kinetic| {
                    const length = kinetic.velocity.length();
                    if (length == 0) continue;
                    if (self.particle_index % 4 == 0) {
                        self.particles.append(self.allocator, Particle{
                            .position = pos,
                            .velocity = dir.scale(0.7),
                            .lifetime = 1,
                            .color = .brown,
                            .kind = .{ .Rectangle = .{ .x = 2, .y = 2 } },
                            .rotation = transform.rotation,
                        }) catch unreachable;
                    } else {
                        self.particles.append(self.allocator, Particle{
                            .position = pos,
                            .velocity = dir.scale(0.7),
                            .lifetime = 1,
                            .color = .dark_brown,
                            .kind = .{ .Rectangle = .{ .x = 2, .y = 2 } },
                            .rotation = transform.rotation,
                        }) catch unreachable;
                    }
                }
                if (e.drift) |drift| {
                    const default_scale = 10;
                    switch (drift.stage) {
                        .none => {},
                        .Mini => {
                            if (self.particle_index % 4 == 0) {
                                self.particles.append(self.allocator, Particle{
                                    .position = pos,
                                    .velocity = dir.scale(1.2),
                                    .lifetime = 1,
                                    .color = .white,
                                    .kind = .{ .Spark = .{ .scale = default_scale, .alt_color = .white, .force = 4 } },
                                    .rotation = transform.rotation,
                                }) catch unreachable;
                            } else if (self.particle_index % 3 == 0) {
                                self.particles.append(self.allocator, Particle{
                                    .position = pos,
                                    .velocity = dir.scale(0.8),
                                    .lifetime = 0.8,
                                    .color = .gray,
                                    .kind = .{ .Spark = .{ .scale = default_scale, .alt_color = .gray, .force = 2 } },
                                    .rotation = transform.rotation,
                                }) catch unreachable;
                            } else if (self.particle_index % 2 == 0) {
                                self.particles.append(self.allocator, Particle{
                                    .position = pos,
                                    .velocity = dir.scale(1),
                                    .lifetime = 1,
                                    .color = .light_gray,
                                    .kind = .{ .Spark = .{ .scale = default_scale, .alt_color = .light_gray, .force = 2 } },
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
                                    .kind = .{ .Spark = .{ .scale = default_scale, .alt_color = .white, .force = 4 } },
                                    .rotation = transform.rotation,
                                }) catch unreachable;
                            } else if (self.particle_index % 3 == 0) {
                                self.particles.append(self.allocator, Particle{
                                    .position = pos,
                                    .velocity = dir.scale(0.8),
                                    .lifetime = 0.8,
                                    .color = .blue,
                                    .kind = .{ .Spark = .{ .scale = default_scale, .alt_color = .blue, .force = 2 } },
                                    .rotation = transform.rotation,
                                }) catch unreachable;
                            } else if (self.particle_index % 2 == 0) {
                                self.particles.append(self.allocator, Particle{
                                    .position = pos,
                                    .velocity = dir.scale(1),
                                    .lifetime = 1,
                                    .color = .sky_blue,
                                    .kind = .{ .Spark = .{ .scale = default_scale, .alt_color = .sky_blue, .force = 2 } },
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
                                    .kind = .{ .Spark = .{ .scale = default_scale, .alt_color = .dark_purple, .force = 4 } },
                                    .rotation = transform.rotation,
                                }) catch unreachable;
                            } else if (self.particle_index % 3 == 0) {
                                self.particles.append(self.allocator, Particle{
                                    .position = pos,
                                    .velocity = dir.scale(0.8),
                                    .lifetime = 0.8,
                                    .color = .purple,
                                    .kind = .{ .Spark = .{ .scale = default_scale, .alt_color = .purple, .force = 2 } },
                                    .rotation = transform.rotation,
                                }) catch unreachable;
                            } else if (self.particle_index % 2 == 0) {
                                self.particles.append(self.allocator, Particle{
                                    .position = pos,
                                    .velocity = dir.scale(1),
                                    .lifetime = 1,
                                    .color = .violet,
                                    .kind = .{ .Spark = .{ .scale = default_scale, .alt_color = .violet, .force = 2 } },
                                    .rotation = transform.rotation,
                                }) catch unreachable;
                            }
                        },
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
                },
            }
        }
    }
};

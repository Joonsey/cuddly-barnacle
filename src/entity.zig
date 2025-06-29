const std = @import("std");
const renderer = @import("renderer.zig");
const prefab = @import("prefabs.zig");
const rl = @import("raylib");
const level = @import("level.zig");
const shared = @import("shared.zig");
const Camera = renderer.Camera;
const Renderable = renderer.Renderable;

pub const Prefab = prefab.Prefab;
pub const EntityId = u32;

pub const Controller = struct {
    const max_speed = 150;
    const acceleration = 100;
    const boost_speed = 250;
    const Self = @This();
    pub fn handle_input(self: Self, kinetic: *Kinetic, drift: *Drift, boost: *Boost, transform: *Transform, deltatime: f32) void {
        _ = self;

        const forward: rl.Vector2 = .{
            .x = @cos(transform.rotation),
            .y = @sin(transform.rotation),
        };

        const forward_normal = forward.normalize();

        const current_speed = kinetic.velocity.length();

        const accel = acceleration;
        const is_grounded = transform.height == 0;

        if (is_grounded and rl.isKeyDown(.w)) {
            if (current_speed < max_speed) {
                kinetic.velocity = forward_normal.scale(@min(current_speed + accel, max_speed));
            }
        }

        if (is_grounded and rl.isKeyDown(.s)) {
            if (current_speed > -max_speed * 0.5) {
                kinetic.velocity.x -= accel * forward.x;
                kinetic.velocity.y -= accel * forward.y;
                kinetic.velocity = kinetic.velocity.normalize();
                kinetic.velocity = kinetic.velocity.scale(max_speed * 0.5);
            }
        }

        const base_rotation_speed = 2 * current_speed / max_speed * deltatime;

        if (drift.is_drifting) {
            if (drift.direction == 0 and is_grounded or is_grounded and kinetic.traction == .Offroad) {
                drift.stage = .none;
                drift.is_drifting = false;
                drift.charge_time = 0;
            }

            if (rl.isKeyDown(.h)) {
                transform.rotation += base_rotation_speed * 0.6 * drift.direction;
            }

            if (rl.isKeyReleased(.h)) {
                const stage = DriftStage.get_stage(drift.charge_time);
                boost.boost_time = DriftStage.get_boost_time(stage);
                drift.direction = 0;
                drift.is_drifting = false;
                drift.charge_time = 0;
                drift.stage = .none;
            }
        } else {
            if (rl.isKeyPressed(.h) and is_grounded) {
                drift.is_drifting = true;
                transform.height += 8;

                if (rl.isKeyDown(.a)) {
                    drift.direction = -1;
                } else if (rl.isKeyDown(.d)) {
                    drift.direction = 1;
                } else {
                    drift.direction = 0;
                }
            }
        }

        if (boost.boost_time > 0) kinetic.velocity = forward_normal.scale(boost_speed);

        const rotation_speed = if (!drift.is_drifting) base_rotation_speed else base_rotation_speed * 0.2;

        if (rl.isKeyDown(.a)) {
            transform.rotation -= rotation_speed;
        }

        if (rl.isKeyDown(.d)) {
            transform.rotation += rotation_speed;
        }
    }
};

pub const Transform = extern struct {
    position: rl.Vector2,
    height: f32 = 0,
    rotation: f32 = 0,
};

pub const RaceContext = extern struct {
    lap: usize = 0,
    checkpoint: usize = 0,
};

pub const FlatParticle = struct {
    velocity: rl.Vector2,
};

pub const StackedParticle = struct {
    weight: f32 = -10,
};

pub const ParticleKind = union(enum) {
    Flat: FlatParticle,
    Stacked: StackedParticle,
};

pub const ParticleEmitter = struct {
    kind: ParticleKind,
    interval: f32 = 0.25,
    current: f32 = 2,
    lifetime: f32 = 2,
    color: rl.Color = .dark_gray,
    direction: rl.Vector2,
};

pub const DriftStage = enum(u8) {
    none,
    Mini,
    Medium,
    Turbo,

    pub fn get_stage(time_held: f32) DriftStage {
        if (time_held > 3) return .Turbo;
        if (time_held > 1.5) return .Medium;
        if (time_held > 0.5) return .Mini;
        return .none;
    }

    pub fn get_boost_time(stage: DriftStage) f32 {
        return switch (stage) {
            .none => 0,
            .Mini => 0.3,
            .Medium => 0.5,
            .Turbo => 1.2,
        };
    }
};

pub const Drift = extern struct {
    stage: DriftStage = .none,
    is_drifting: bool = false,
    direction: f32 = 0,
    charge_time: f32 = 0,
};

pub const Boost = extern struct {
    boost_time: f32 = 0,
};

pub const NameTag = extern struct {
    name: [16]u8,

    pub fn draw(self: NameTag, transform: Transform, camera: Camera) void {
        const text = rl.textFormat("%s", .{&self.name});
        const font_size = 10;
        const y_offset = transform.height + 20;
        const text_size = rl.measureText(text, font_size);
        const text_half_size: f32 = @floatFromInt(@divFloor(text_size, 2));

        const rel_position = camera.get_relative_position(transform.position);
        const text_position = rel_position.subtract(.{ .x = text_half_size, .y = y_offset });
        rl.drawText(text, @intFromFloat(text_position.x), @intFromFloat(text_position.y), font_size, .white);
        rl.drawLineV(.init(rel_position.x - text_half_size, rel_position.y - y_offset + font_size), .init(rel_position.x + text_half_size, rel_position.y - y_offset + font_size), .white);
    }
};

pub const Kinetic = extern struct {
    velocity: rl.Vector2,
    friction: f32 = 0.8,
    speed_multiplier: f32 = 1,
    weight: f32 = 40,
    traction: level.Traction = .Track,
};

pub const Archetype = enum {
    None,
    Dead,
    Car,
    Obstacle,
    Missile,
    Wall,
    ItemBox,
    Particle,
    ParticleEmitter,
};

pub const Timer = struct {
    timer: f32 = 1,
};

fn order_by_camera_position(camera: Camera, lhs: Entity, rhs: Entity) bool {
    if (lhs.transform) |lhs_transform| {
        const abs_position = lhs_transform.position;
        const lhs_relative_position = camera.get_relative_position(abs_position);

        if (rhs.transform) |rhs_transform| {
            const rhs_abs_position = rhs_transform.position;
            const rhs_relative_position = camera.get_relative_position(rhs_abs_position);

            return rhs_relative_position.y > lhs_relative_position.y;
        }
    }

    return false;
}

pub const Shadow = struct {
    radius: f32 = 0,
    color: rl.Color = .init(0, 0, 0, 125),
};

pub const Target = extern struct {
    id: EntityId,
};

pub const Spinout = extern struct {
    remaining_time: f32 = 1,
    total_duration: f32 = 1,
    original_rotation: f32,
};

pub const Collider = rl.Rectangle;

pub const Entity = struct {
    renderable: ?Renderable = null,
    kinetic: ?Kinetic = null,
    collision: ?Collider = null,
    controller: ?Controller = null,
    transform: ?Transform = null,
    shadow: ?Shadow = null,
    archetype: Archetype = .None,
    prefab: ?Prefab = null,
    race_context: ?RaceContext = null,
    drift: ?Drift = null,
    boost: ?Boost = null,
    timer: ?Timer = null,
    name_tag: ?NameTag = null,
    target: ?Target = null,
    spinout: ?Spinout = null,
    particle_emitter: ?ParticleEmitter = null,

    const Self = @This();
    pub fn update(self: *Self, deltatime: f32) ?Event {
        const event: ?Event = null;
        if (self.controller) |controller| {
            if (self.kinetic) |*kinetic| {
                if (self.drift) |*drift| {
                    if (self.transform) |*transform| {
                        if (self.boost) |*boost| {
                            if (self.spinout == null) controller.handle_input(kinetic, drift, boost, transform, deltatime);
                        }
                    }
                }
            }
        }

        if (self.collision) |*collision| {
            if (self.transform) |transform| {
                collision.x = transform.position.x - (collision.width / 2);
                collision.y = transform.position.y - (collision.height / 2);
            }
        }

        if (self.timer) |*timer| {
            timer.timer = @max(timer.timer - deltatime, 0);
        }

        if (self.spinout) |*spinout| {
            spinout.remaining_time -= deltatime;

            if (spinout.remaining_time <= 0) {
                self.spinout = null;
            } else if (self.transform) |*transform| {
                const t = 1.0 - (spinout.remaining_time / spinout.total_duration);
                const spin_angle = std.math.tau * 3.0 * t; // 3 full spins during the duration

                transform.rotation = spinout.original_rotation + spin_angle;
            }
        }

        return event;
    }

    pub fn draw(self: Self, camera: Camera) void {
        if (self.transform) |transform| {
            const pos = transform.position;
            if (camera.is_out_of_bounds(pos)) return;
            if (self.renderable) |renderable| {
                if (self.shadow) |shadow| {
                    rl.drawCircleV(camera.get_relative_position(pos), shadow.radius, shadow.color);
                }

                switch (renderable) {
                    .Flat => |sprite| {
                        sprite.draw(camera, transform);
                    },
                    .Stacked => |sprite| {
                        sprite.draw(camera, transform);
                    },
                }
            }

            if (self.name_tag) |name_tag| name_tag.draw(transform, camera);
        }
    }
};

pub const Event = union(enum) {
    Collision: struct {
        a: EntityId,
        b: EntityId,
    },
    Finish: struct {
        placement: usize,
        entity: EntityId,
    },
    CompleteLap: struct {
        placement: usize,
        entity: EntityId,
    },
    Voided: struct {
        entity: EntityId,
        position: rl.Vector2,
    },
    Boosting: struct {
        // maybe level of boost?? more things?
        entity: EntityId,
    },
};

const EventListenerFn = *const fn (*anyopaque, *ECS, Event) void;

const Observer = struct {
    callback: EventListenerFn,
    context: *anyopaque,
};

pub const ECS = struct {
    entities: std.ArrayListUnmanaged(Entity),
    events: std.ArrayListUnmanaged(Event),
    next_id: EntityId = 0,
    recycle_array: std.ArrayListUnmanaged(EntityId),

    event_listeners: std.ArrayListUnmanaged(Observer),

    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .entities = .{},
            .events = .{},
            .recycle_array = .{},
            .allocator = allocator,
            .event_listeners = .{},
        };
    }

    pub fn register_observer(self: *Self, observer: Observer) void {
        self.event_listeners.append(self.allocator, observer) catch unreachable;
    }

    fn notify(self: *Self, event: Event) void {
        for (self.event_listeners.items) |observer| observer.callback(observer.context, self, event);
    }

    fn handle_events(self: *Self) void {
        for (self.events.items) |event| {
            self.notify(event);
            switch (event) {
                .Collision => |col| {
                    const a = &self.entities.items[col.a];
                    const b = &self.entities.items[col.b];
                    if (a.archetype == .ItemBox and (b.archetype == .Car or b.archetype == .Missile)) {
                        a.renderable = null;
                        a.renderable = null;
                        a.timer = .{ .timer = 1 };
                    } else if (b.archetype == .ItemBox and (a.archetype == .Car or a.archetype == .Missile)) {
                        b.collision = null;
                        b.renderable = null;
                        b.timer = .{ .timer = 1 };
                    } else if (a.archetype == .Car and b.archetype == .Car) {
                        const a_transform = &a.transform.?;
                        const b_transform = &b.transform.?;

                        const a_kinetic = &a.kinetic.?;
                        const b_kinetic = &b.kinetic.?;

                        const a_delta = b_transform.position.subtract(a_transform.position);

                        const normal = a_delta.normalize();
                        const correction = normal.scale(b_transform.position.distance(a_transform.position) / 2);
                        a_transform.position = a_transform.position.subtract(correction);
                        b_transform.position = b_transform.position.add(correction);

                        const relative_vel = b_kinetic.velocity.subtract(a_kinetic.velocity);
                        const vel_along_normal = relative_vel.dotProduct(normal);
                        const restitution = 0.5;
                        const impulse_scalar = -(1 + restitution) * vel_along_normal / 2;
                        const impulse = normal.scale(impulse_scalar);

                        // works! but might need some tweaks

                        a_kinetic.velocity = a_kinetic.velocity.subtract(impulse);
                        b_kinetic.velocity = b_kinetic.velocity.add(impulse);
                    } else if (a.archetype == .Missile and b.archetype == .Car) {
                        self.kill(col.a);
                        b.spinout = .{ .original_rotation = b.transform.?.rotation };
                        if (b.drift) |_| b.drift = .{};
                    } else if (b.archetype == .Missile and a.archetype == .Car) {
                        self.kill(col.b);
                        a.spinout = .{ .original_rotation = a.transform.?.rotation };
                        if (a.drift) |_| a.drift = .{};
                    } else if (b.archetype == .Missile) {
                        self.kill(col.b);
                    } else if (a.archetype == .Missile) {
                        self.kill(col.a);
                    }
                },
                .Finish => |fin| {
                    _ = fin;
                },
                .CompleteLap => |cmp| {
                    _ = cmp;
                },
                .Boosting => |boost| {
                    _ = boost;
                },
                .Voided => |voided| {
                    _ = voided;
                },
            }
        }

        self.events.items.len = 0;
    }

    pub fn update(self: *Self, deltatime: f32, lvl: level.Level) void {
        for (self.entities.items) |*entity| {
            if (entity.update(deltatime)) |event| self.events.append(self.allocator, event) catch unreachable;
        }

        for (0..self.entities.items.len) |i| {
            var entity = &self.entities.items[i];
            if (entity.drift) |*drift| {
                if (drift.is_drifting) {
                    drift.charge_time += deltatime;
                    drift.stage = DriftStage.get_stage(drift.charge_time);
                }
            }
            if (entity.boost) |*boost| {
                boost.boost_time = @max(boost.boost_time - deltatime, 0);
            }
            if (entity.transform) |*transform| {
                var position = transform.position;
                if (entity.kinetic) |*kinetic| {
                    kinetic.traction = lvl.get_traction(transform.position);
                    kinetic.speed_multiplier = kinetic.traction.speed_multiplier();
                    kinetic.friction = kinetic.traction.friction();

                    transform.height = @max(transform.height - (kinetic.weight * deltatime), 0);
                    if (transform.height == 0 and kinetic.traction == .Void) {
                        self.events.append(self.allocator, .{ .Voided = .{ .entity = @intCast(i), .position = transform.position } }) catch unreachable;
                        if (entity.race_context) |rc| {
                            position = lvl.checkpoints[rc.checkpoint].position;
                            transform.height = 50;
                            kinetic.velocity = .init(0, 0);
                            if (entity.boost) |*boost| boost.boost_time = 0;
                            if (entity.drift) |*drift| {
                                drift.charge_time = 0;
                                drift.is_drifting = false;
                                drift.direction = 0;
                            }

                            const next = lvl.checkpoints[(rc.checkpoint + 1) % lvl.checkpoints.len];
                            const rotation = std.math.atan2(next.position.y - position.y, next.position.x - position.x);
                            transform.rotation = rotation;
                        }
                    }

                    if (entity.collision) |*collision| {
                        const sample_pos = position.add(kinetic.velocity.scale(deltatime).scale(kinetic.speed_multiplier));
                        collision.x = sample_pos.x - collision.width / 2;
                        var collided = false;
                        for (0..self.entities.items.len) |o| {
                            if (o == i) continue;
                            const other = &self.entities.items[o];
                            if (other.collision) |other_collision| {
                                if (collision.checkCollision(other_collision)) {
                                    self.events.append(self.allocator, .{ .Collision = .{ .a = @intCast(i), .b = @intCast(o) } }) catch unreachable;
                                    collided = true;
                                }
                            }
                        }

                        if (collided) {
                            collision.x = position.x - collision.width / 2;
                        } else {
                            position.x = sample_pos.x;
                        }

                        collision.y = sample_pos.y - collision.height / 2;
                        collided = false;
                        for (0..self.entities.items.len) |o| {
                            if (o == i) continue;
                            const other = &self.entities.items[o];
                            if (other.collision) |other_collision| {
                                if (collision.checkCollision(other_collision)) {
                                    self.events.append(self.allocator, .{ .Collision = .{ .a = @intCast(i), .b = @intCast(o) } }) catch unreachable;
                                    collided = true;
                                }
                            }
                        }

                        if (collided) {
                            collision.y = position.y - collision.height / 2;
                        } else {
                            position.y = sample_pos.y;
                        }
                    } else {
                        position = position.add(kinetic.velocity.scale(deltatime).scale(kinetic.speed_multiplier));
                    }

                    if (transform.height == 0) {
                        kinetic.velocity.x *= kinetic.friction;
                        kinetic.velocity.y *= kinetic.friction;
                    } else if (entity.boost) |boost| if (boost.boost_time > 0) {
                        kinetic.velocity.x *= kinetic.friction;
                        kinetic.velocity.y *= kinetic.friction;
                    };

                    if (kinetic.velocity.length() < 0.1) kinetic.velocity = .init(0, 0);
                }

                transform.position = position;

                if (entity.race_context) |*race_context| {
                    const next_expected_checkpoint = race_context.checkpoint + 1;
                    if (next_expected_checkpoint >= lvl.checkpoints.len) {
                        if (lvl.finish.is_intersecting(transform.position, 9)) {
                            race_context.checkpoint = 0;
                            race_context.lap += 1;

                            if (race_context.lap == shared.MAX_LAPS) {
                                self.events.append(self.allocator, .{ .Finish = .{ .placement = 0, .entity = @intCast(i) } }) catch unreachable;
                            } else {
                                self.events.append(self.allocator, .{ .CompleteLap = .{ .placement = 0, .entity = @intCast(i) } }) catch unreachable;
                            }
                        }
                    } else {
                        const cp = lvl.checkpoints[next_expected_checkpoint];
                        if (rl.checkCollisionCircles(cp.position, cp.radius, transform.position, 9)) {
                            race_context.checkpoint += 1;
                        }
                    }
                }

                if (entity.particle_emitter) |*pe| {
                    if (pe.current == 0) pe.current = pe.interval;
                    pe.current = @max(pe.current - deltatime, 0);
                }
            }

            switch (entity.archetype) {
                .ItemBox => {
                    if (entity.transform) |*transform| {
                        const abs_time_offset: f32 = @floatCast(rl.getTime() + @as(f64, @floatFromInt(i)));
                        transform.height = 5 + 10 * @abs(@sin(abs_time_offset));
                        transform.rotation = 0.25 * abs_time_offset + @as(f32, @floatFromInt(i));
                    }
                    if (entity.timer) |timer| {
                        if (timer.timer <= 0) {
                            const ref = prefab.get(.itembox);
                            entity.renderable = ref.renderable;
                            entity.collision = ref.collision;
                            entity.timer = null;
                        }
                    }
                },
                .Particle => {
                    if (entity.timer) |timer| {
                        if (timer.timer <= 0) {
                            self.kill(@intCast(i));
                        }
                    }
                },
                .Missile => {
                    if (entity.timer) |timer| {
                        if (timer.timer <= 0) {
                            entity.collision = .{ .x = 0, .y = 0, .width = 16, .height = 16 };
                            entity.timer = null;
                        }
                    }
                    if (entity.target) |target_component| {
                        const speed = 200;
                        const target_entity = self.get(target_component.id);
                        if (entity.kinetic) |*kinetic| {
                            if (entity.transform) |*transform| {
                                if (entity.race_context) |missile_rc| {
                                    if (target_entity.race_context) |target_rc| {
                                        if (missile_rc.checkpoint == target_rc.checkpoint) {
                                            // travel towards target
                                            if (target_entity.transform) |target_transform| {
                                                update_velocity_with_rotation_constraint(transform, kinetic, target_transform.position, speed, 1 * deltatime);
                                            }
                                        } else {
                                            // travel towards next checkpoint
                                            const next_expected_checkpoint_idx = (missile_rc.checkpoint + 1) % lvl.checkpoints.len;
                                            const next_expected_checkpoint = lvl.checkpoints[next_expected_checkpoint_idx];

                                            update_velocity_with_rotation_constraint(transform, kinetic, next_expected_checkpoint.position, speed, 1 * deltatime);
                                        }
                                    }
                                }
                            }
                        }
                    }
                },
                else => {},
            }
        }

        self.handle_events();
    }

    pub fn draw(self: Self, camera: Camera) void {
        var array: std.ArrayListUnmanaged(Entity) = .{};
        array.appendSlice(self.allocator, self.entities.items) catch unreachable;
        defer array.deinit(self.allocator);

        std.mem.sort(Entity, array.items, camera, order_by_camera_position);
        for (array.items) |entity| entity.draw(camera);
    }

    pub fn kill(self: *Self, id: EntityId) void {
        const entity = self.get_mut(id);
        entity.archetype = .Dead;
        entity.boost = null;
        entity.collision = null;
        entity.controller = null;
        entity.drift = null;
        entity.kinetic = null;
        entity.name_tag = null;
        entity.prefab = null;
        entity.race_context = null;
        entity.renderable = null;
        entity.shadow = null;
        entity.target = null;
        entity.timer = null;
        entity.transform = null;

        self.recycle_array.append(self.allocator, id) catch unreachable;
    }

    pub fn spawn(self: *Self, entity: Entity) EntityId {
        if (self.recycle_array.pop()) |id| {
            std.debug.assert(self.entities.items.len > id);
            std.debug.assert(self.entities.items[id].archetype == .Dead);
            self.entities.items[id] = entity;
            return id;
        } else {
            self.entities.append(self.allocator, entity) catch unreachable;
            defer self.next_id += 1;
            return self.next_id;
        }
    }

    pub fn despawn(self: *Self, id: EntityId) void {
        self.next_id -= 1;
        _ = self.entities.swapRemove(id);
    }

    pub fn get(self: *Self, id: EntityId) Entity {
        return self.entities.items[id];
    }

    pub fn get_mut(self: *Self, id: EntityId) *Entity {
        return &self.entities.items[id];
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit(self.allocator);
        self.entities.deinit(self.allocator);
        self.event_listeners.deinit(self.allocator);
        self.recycle_array.deinit(self.allocator);
    }
};

fn rotate_towards(current: f32, target: f32, max_delta: f32) f32 {
    var delta = target - current;
    // Normalize to [-PI, PI]
    delta = std.math.atan2(std.math.sin(delta), std.math.cos(delta));
    return current + std.math.clamp(delta, -max_delta, max_delta);
}

// Common function to calculate velocity with rotation constraint
fn update_velocity_with_rotation_constraint(
    transform: *Transform,
    kinetic: *Kinetic,
    target_pos: rl.Vector2,
    speed: f32,
    max_rotation_rad: f32,
) void {
    const dir = target_pos.subtract(transform.position);
    const desired_angle = std.math.atan2(dir.y, dir.x);
    transform.rotation = rotate_towards(transform.rotation, desired_angle, max_rotation_rad);

    // Now get new forward direction from updated rotation
    const new_dir = rl.Vector2{
        .x = std.math.cos(transform.rotation),
        .y = std.math.sin(transform.rotation),
    };

    kinetic.velocity = new_dir.scale(speed);
}

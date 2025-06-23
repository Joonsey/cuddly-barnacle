const std = @import("std");
const renderer = @import("renderer.zig");
const prefab = @import("prefabs.zig");
const rl = @import("raylib");
const level = @import("level.zig");
const Camera = renderer.Camera;
const Renderable = renderer.Renderable;

pub const Prefab = prefab.Prefab;
pub const EntityId = u32;

pub const Controller = struct {
    const max_speed = 100;
    const acceleration = 150;
    const Self = @This();
    pub fn handle_input(self: Self, kinetic: *Kinetic, drift: *Drift, boost: *Boost, transform: *Transform, deltatime: f32) void {
        _ = self;

        const forward: rl.Vector2 = .{
            .x = @cos(transform.rotation),
            .y = @sin(transform.rotation),
        };

        const current_speed = kinetic.velocity.length();

        const accel = acceleration * 1;

        if (rl.isKeyDown(.w)) {
            if (current_speed < max_speed) {
                kinetic.velocity.x += accel * forward.x;
                kinetic.velocity.y += accel * forward.y;
            }
        }

        if (rl.isKeyDown(.s)) {
            if (current_speed > -max_speed * 0.5) {
                kinetic.velocity.x -= accel * forward.x;
                kinetic.velocity.y -= accel * forward.y;
            }
        }

        const base_rotation_speed = kinetic.velocity.length() / max_speed * deltatime;

        if (drift.is_drifting) {
            if (drift.direction == 0 and transform.height == 0) {
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
            if (rl.isKeyPressed(.h) and transform.height == 0) {
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

        if (boost.boost_time > 0) {
            kinetic.velocity.x += accel * forward.x;
            kinetic.velocity.y += accel * forward.y;
        }
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

pub const Kinetic = extern struct {
    velocity: rl.Vector2,
    friction: f32 = 0.8,
    speed_multiplier: f32 = 1,
    weight: f32 = 20,
};

pub const Archetype = enum {
    None,
    Car,
    Obstacle,
    Wall,
    ItemBox,
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

pub const Entity = struct {
    renderable: ?Renderable = null,
    kinetic: ?Kinetic = null,
    collision: ?rl.Rectangle = null,
    controller: ?Controller = null,
    transform: ?Transform = null,
    shadow: ?Shadow = null,
    archetype: Archetype = .None,
    prefab: ?Prefab = null,
    race_context: ?RaceContext = null,
    drift: ?Drift = null,
    boost: ?Boost = null,
    timer: ?Timer = null,

    const Self = @This();
    pub fn update(self: *Self, deltatime: f32) ?Event {
        const event: ?Event = null;
        if (self.controller) |controller| {
            if (self.kinetic) |*kinetic| {
                if (self.drift) |*drift| {
                    if (self.transform) |*transform| {
                        if (self.boost) |*boost| {
                            controller.handle_input(kinetic, drift, boost, transform, deltatime);
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

        return event;
    }

    pub fn draw(self: Self, camera: Camera) void {
        if (self.transform) |transform| {
            const pos = transform.position;
            if (self.renderable) |renderable| {
                if (self.shadow) |shadow| {
                    if (!camera.is_out_of_bounds(pos)) {
                        rl.drawCircleV(camera.get_relative_position(pos), shadow.radius, shadow.color);
                    }
                }

                switch (renderable) {
                    .Flat => |sprite| {
                        if (!camera.is_out_of_bounds(pos)) sprite.draw(camera, transform);
                    },
                    .Stacked => |sprite| {
                        if (!camera.is_out_of_bounds(pos)) sprite.draw(camera, transform);
                    },
                }
            }
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

    event_listeners: std.ArrayListUnmanaged(Observer),

    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .entities = .{},
            .events = .{},
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
                    if (a.archetype == .ItemBox and b.archetype == .Car) {
                        a.renderable = null;
                        a.renderable = null;
                        a.timer = .{ .timer = 1 };
                    }
                    if (b.archetype == .ItemBox and a.archetype == .Car) {
                        b.collision = null;
                        b.renderable = null;
                        b.timer = .{ .timer = 1 };
                    }
                },
                .Finish => |fin| {
                    std.log.err("{any}", .{fin});
                },
                .CompleteLap => |cmp| {
                    _ = cmp;
                },
                .Boosting => |boost| {
                    _ = boost;
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
                    transform.height = @max(transform.height - (kinetic.weight * deltatime), 0);
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

                    kinetic.velocity.x *= kinetic.friction * deltatime;
                    kinetic.velocity.y *= kinetic.friction * deltatime;
                }

                transform.position = position;

                if (entity.race_context) |*race_context| {
                    const next_expected_checkpoint = race_context.checkpoint + 1;
                    if (next_expected_checkpoint >= lvl.checkpoints.len) {
                        if (lvl.finish.is_intersecting(transform.position, 9)) {
                            race_context.checkpoint = 0;
                            race_context.lap += 1;

                            if (race_context.lap >= 3) {
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
            }

            if (entity.archetype == .ItemBox) {
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

    pub fn spawn(self: *Self, entity: Entity) EntityId {
        self.entities.append(self.allocator, entity) catch unreachable;
        defer self.next_id += 1;
        return self.next_id;
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
    }
};

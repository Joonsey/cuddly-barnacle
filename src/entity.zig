const std = @import("std");
const renderer = @import("renderer.zig");
const rl = @import("raylib");
const Camera = renderer.Camera;
const Renderable = renderer.Renderable;

pub const EntityId = u32;

pub const Controller = struct {
    const max_speed = 100;
    const acceleration = 150;
    const Self = @This();
    pub fn handle_input(self: Self, kinetic: *Kinetic, deltatime: f32) void {
        _ = self;

        const forward: rl.Vector2 = .{
            .x = @cos(kinetic.rotation),
            .y = @sin(kinetic.rotation),
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

        const rotation_speed = (1.5 * (kinetic.velocity.length() / max_speed)) * deltatime;

        if (rl.isKeyDown(.a)) {
            kinetic.rotation -= rotation_speed;
        }

        if (rl.isKeyDown(.d)) {
            kinetic.rotation += rotation_speed;
        }
    }
};

pub const Kinetic = struct {
    position: rl.Vector2,
    velocity: rl.Vector2,
    rotation: f32,
    friction: f32 = 0.8,
    speed_multiplier: f32 = 1,
};

pub const Archetype = enum {
    None,
    Car,
    Obstacle,
    Wall,
};

pub const Entity = struct {
    renderable: ?Renderable = null,
    kinetic: ?Kinetic = null,
    collision: ?rl.Rectangle = null,
    controller: ?Controller = null,
    archetype: Archetype = .None,

    const Self = @This();
    pub fn update(self: *Self, deltatime: f32) ?Event {
        const event: ?Event = null;
        if (self.kinetic) |kinetic| {
            if (self.renderable) |*renderable| {
                switch (renderable.*) {
                    .Flat  => |*sprite| {
                        sprite.position = kinetic.position;
                        sprite.rotation = kinetic.rotation;
                    },
                    .Stacked => |*sprite| {
                        sprite.position = kinetic.position;
                        sprite.rotation = kinetic.rotation;
                    },
                }
            }
        }
        if (self.controller) |controller| {
            if (self.kinetic) |*kinetic| {
                controller.handle_input(kinetic, deltatime);
            }
        }

        return event;
    }

    pub fn draw(self: Self, camera: Camera) void {
        if (self.renderable) |renderable| {
            switch (renderable) {
                .Flat => |sprite| {
                    if (!camera.is_out_of_bounds(sprite.position)) sprite.draw(camera);
                },
                .Stacked => |sprite| {
                    if (!camera.is_out_of_bounds(sprite.position)) sprite.draw(camera);
                },
            }
        }
    }
};

const Event = union(enum) {
    Collision: struct {
        a: EntityId,
        b: EntityId,
    },
};

pub const ECS = struct {
    entities: std.ArrayListUnmanaged(Entity),
    events: std.ArrayListUnmanaged(Event),
    next_id: EntityId = 0,

    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .entities = .{},
            .events = .{},
            .allocator = allocator,
        };
    }

    fn handle_events(self: *Self) void {
        for (self.events.items) |event| {
            switch (event) {
                .Collision => |col| {
                    _ = col;
                    // std.log.err("COLLISION EVENT {?}", .{col});
                },
            }
        }

        self.events.items.len = 0;
    }

    pub fn update(self: *Self, deltatime: f32) void {
        for (self.entities.items) |*entity| {
            if (entity.update(deltatime)) |event| self.events.append(self.allocator, event) catch unreachable;
        }

        for (0..self.entities.items.len) |i| {
            var entity = &self.entities.items[i];
            if (entity.kinetic) |*kinetic| {
                if (entity.collision) |*collision| {
                    const sample_pos = kinetic.position.add(kinetic.velocity.scale(deltatime).scale(kinetic.speed_multiplier));
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
                        collision.x = kinetic.position.x - collision.width / 2;
                    } else {
                        kinetic.position.x = sample_pos.x;
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
                        collision.y = kinetic.position.y - collision.height / 2;
                    } else {
                        kinetic.position.y = sample_pos.y;
                    }
                } else {
                    kinetic.position = kinetic.position.add(kinetic.velocity.scale(deltatime).scale(kinetic.speed_multiplier));
                }

                kinetic.velocity.x *= kinetic.friction * deltatime;
                kinetic.velocity.y *= kinetic.friction * deltatime;
            }
        }

        self.handle_events();
    }

    pub fn draw(self: Self, camera: Camera) void {
        for (self.entities.items) |entity| entity.draw(camera);
    }

    pub fn spawn(self: *Self, entity: Entity) EntityId {
        self.entities.append(self.allocator, entity) catch unreachable;
        defer self.next_id += 1;
        return self.next_id;
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
    }
};

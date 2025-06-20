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

const Gamestate = struct {
    ecs: entity.ECS,
    level: Level,
    camera: renderer.Camera,
    tracks: Tracks,

    allocator: std.mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, comptime lvl_path: []const u8) !Self {
        return .{
            .ecs = .init(allocator),
            .level = try .init(lvl_path, allocator),
            .camera = .init(RENDER_WIDTH, RENDER_HEIGHT),
            .tracks = try .init(allocator),

            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.ecs.deinit();
        self.level.deinit(self.allocator);
        self.tracks.deinit();
    }

    pub fn update(self: *Self, deltatime: f32) void {
        self.ecs.update(deltatime, self.level);
        self.level.update_intermediate_texture(self.camera);
        self.tracks.update(&self.ecs);
    }

    pub fn draw(self: Self) void {
        self.level.draw(self.camera);
        self.tracks.draw(self.camera);
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

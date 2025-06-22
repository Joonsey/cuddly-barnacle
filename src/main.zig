const std = @import("std");
const rl = @import("raylib");

const renderer = @import("renderer.zig");
const entity = @import("entity.zig");
const Level = @import("level.zig").Level;
const Levels = @import("level.zig").Levels;

const prefab = @import("prefabs.zig");
const Tracks = @import("tracks.zig").Tracks;
const Particles = @import("particles.zig").Particles;

var WINDOW_WIDTH: i32 = 1600;
var WINDOW_HEIGHT: i32 = 900;
const RENDER_WIDTH: i32 = 720;
const RENDER_HEIGHT: i32 = 480;

const Items = enum(u8) {
    Boost,
};

const inventory = struct {
    item: ?Items,
    random: std.Random,

    player_id: entity.EntityId,

    allocator: std.mem.Allocator,
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, seed: u64) Self {
        var rand = std.Random.DefaultPrng.init(seed);
        return .{
            .item = null,
            .allocator = allocator,
            .random = rand.random(),
            .player_id = 0,
        };
    }

    pub fn generate_item(self: *Self, eligible_items: []Items) void {
        if (self.item) |_| return;
        std.debug.assert(eligible_items.len > 0);
        const chosen = self.random.intRangeAtMost(usize, 0, eligible_items.len - 1);
        self.item = eligible_items[chosen];
    }

    pub fn draw(self: Self) void {
        const text: [:0]const u8 = if (self.item) |item| @tagName(item) else comptime "none";
        rl.drawText(text, 0, 32, 20, .white);
    }

    pub fn set_player(self: *Self, new_player_id: entity.EntityId) void {
        self.player_id = new_player_id;
    }

    pub fn on_event(s: *anyopaque, ecs: *entity.ECS, event: entity.Event) void {
        const self: *Self = @alignCast(@ptrCast(s));
        switch (event) {
            .Collision => |col| {
                const a = ecs.get(col.a);
                const b = ecs.get(col.b);
                if (a.archetype == .ItemBox and col.b == self.player_id or b.archetype == .ItemBox and col.a == self.player_id) {
                    var eligible_items: std.ArrayListUnmanaged(Items) = .{};
                    eligible_items.append(self.allocator, Items.Boost) catch unreachable;
                    self.generate_item(eligible_items.items);
                    eligible_items.deinit(self.allocator);
                }
            },
            else => {},
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        return;
    }
};

const Gamestate = struct {
    ecs: entity.ECS,
    level: Level,
    camera: renderer.Camera,
    tracks: Tracks,
    particles: Particles,
    inventory: inventory,

    allocator: std.mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, comptime lvl_path: []const u8) !Self {
        return .{
            .ecs = .init(allocator),
            .level = try .init(lvl_path, allocator),
            .camera = .init(RENDER_WIDTH, RENDER_HEIGHT),
            .tracks = try .init(allocator),
            .particles = .init(allocator),
            .inventory = .init(allocator, 289289),

            .allocator = allocator,
        };
    }

    pub fn use_item(self: *Self) void {
        if (self.inventory.item) |item| switch (item) {
            .Boost => {
                if (self.ecs.get_mut(self.inventory.player_id).drift) |*drift| {
                    const turbo = entity.DriftState.BoostStage.Turbo;
                    drift.state = .{ .boosting = turbo };
                    drift.boost_time = entity.DriftState.BoostStage.get_boost_time(turbo);
                }
            },
        };

        self.inventory.item = null;
    }

    pub fn deinit(self: *Self) void {
        self.ecs.deinit();
        self.level.deinit(self.allocator);
        self.tracks.deinit();
        self.particles.deinit();
        self.inventory.deinit();
    }

    pub fn update(self: *Self, deltatime: f32) void {
        self.ecs.update(deltatime, self.level);
        self.level.update_intermediate_texture(self.camera);
        self.tracks.update(&self.ecs);
        self.particles.update(deltatime, self.ecs);

        if (rl.isKeyPressed(.j)) self.use_item();
    }

    pub fn draw(self: Self) void {
        self.level.draw(self.camera);
        self.tracks.draw(self.camera);
        self.particles.draw(self.camera);
        self.ecs.draw(self.camera);

        self.inventory.draw();
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

    state.ecs.register_observer(.{ .callback = &Particles.on_event, .context = &state.particles });
    state.ecs.register_observer(.{ .callback = &inventory.on_event, .context = &state.inventory });

    state.level.load_ecs(&state.ecs);

    var tank = prefab.get(.tank);
    tank.transform.?.position = state.level.finish.get_spawn(0);
    tank.transform.?.rotation = state.level.finish.get_direction();
    tank.kinetic = .{ .velocity = .{ .x = 0, .y = 0 } };
    tank.controller = .{};
    tank.drift = .{};
    tank.race_context = .{};
    const player_id = state.ecs.spawn(tank);
    state.inventory.set_player(player_id);

    const scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT);

    rl.setTargetFPS(144);
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

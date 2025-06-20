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

const Gamestate = struct {
    ecs: entity.ECS,
    level: Level,
    camera: renderer.Camera,

    level_shader: rl.Shader,

    allocator: std.mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, comptime lvl_path: []const u8) !Self {
        return .{
            .ecs = .init(allocator),
            .level = try .init(lvl_path, allocator),
            .camera = .init(RENDER_WIDTH, RENDER_HEIGHT),
            .allocator = allocator,

            .level_shader = try rl.loadShader(
                null,
                "assets/shaders/world.fs",
            ),
        };
    }

    pub fn deinit(self: *Self) void {
        self.ecs.deinit();
        self.level.deinit(self.allocator);
    }

    pub fn update(self: *Self, deltatime: f32) void {
        self.ecs.update(deltatime, self.level);
        self.level.update_intermediate_texture(self.camera);
    }

    pub fn draw(self: Self) void {
        self.level.draw(self.level_shader, self.camera);
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
    tank.transform.?.position = state.level.finish.get_spawn(11);
    tank.kinetic = .{ .rotation = state.level.finish.get_direction(), .velocity = .{ .x = 0, .y = 0 }};
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
        const delta = kinetics.rotation + std.math.pi * 0.5 - state.camera.rotation;
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

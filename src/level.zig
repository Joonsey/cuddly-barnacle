const std = @import("std");
const rl = @import("raylib");
const renderer = @import("renderer.zig");
const entity = @import("entity.zig");


pub const Levels = struct {
    pub const level_one: []const u8 = "level1";
};

const Metadata = struct {
    pub fn load(path: []const u8) !Metadata {
        _ = path;
        return error.NotFound;
    }
};

fn color_equal(clr: rl.Color, comptime other: rl.Color) bool {
    return clr.a == other.a and clr.b == other.b and clr.r == other.r and clr.a == other.a;
}

pub const Traction = enum {
    Track,
    Offroad,
    Slippery,

    pub fn from_pixel(clr: rl.Color) Traction {
        if (color_equal(clr, .white)) return .Track;
        return .Offroad;
    }

    pub fn friction(self: Traction) f32 {
        return switch (self) {
            .Track => 0.8,
            .Offroad => 0.2,
            .Slippery => 0.99,
        };
    }

    pub fn speed_multiplier(self: Traction) f32 {
        return switch (self) {
            .Track => 1.2,
            .Offroad => 0.6,
            .Slippery => 1.0,
        };
    }
};

pub const Level = struct {
    physics_image: rl.Image,
    graphics_texture: rl.Texture,
    intermediate_texture: rl.RenderTexture,
    metadata: Metadata,

    startup_entities: []entity.Entity,

    const BinEntity = struct {
        archetype: entity.Archetype,
        renderable: ?renderer.Rendertypes,
        path: ?[:0]const u8,
        position: ?rl.Vector2,
        collision: ?rl.Rectangle,
    };

    const Self = @This();
    const levels_path = "assets/levels/";
    pub fn init(comptime directory: []const u8, allocator: std.mem.Allocator) !Self {
        const text = try rl.loadTexture(levels_path ++ directory ++ "/graphics.png");
        return .{
            .physics_image = try rl.loadImage(levels_path ++ directory ++ "/physics.png"),
            .graphics_texture = text,
            .intermediate_texture = try rl.loadRenderTexture(720, 480),
            .metadata = Metadata.load(levels_path ++ directory ++ "/metadata") catch .{},
            .startup_entities = try load_entities_from_file(levels_path ++ directory ++ "/entities", allocator),
        };
    }

    pub fn load_ecs(self: Self, ecs: *entity.ECS) void {
        if (self.startup_entities.len == 0) return;
        for (self.startup_entities) |e| {
            _ = ecs.spawn(e);
        }
    }

    pub fn update_intermediate_texture(self: *Self, camera: renderer.Camera) void {
        self.intermediate_texture.begin();
        rl.clearBackground(.black);
        const relative_pos = camera.get_relative_position(.{ .x = 0, .y = 0 });

        const texture = self.graphics_texture;
        const f_width: f32 = @floatFromInt(texture.width);
        const f_height: f32 = @floatFromInt(texture.height);
        texture.drawPro(
            .{ .x = 0, .y = 0, .width = f_width, .height = f_height},
            .{ .x = relative_pos.x, .y = relative_pos.y, .width = f_width, .height = f_height},
            .{ .x = 0, .y = 0 },
            std.math.radiansToDegrees(-camera.rotation),
            .white,
        );
        self.intermediate_texture.end();
    }

    fn load_entities_from_file(path: []const u8, allocator: std.mem.Allocator) ![]entity.Entity {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const buf = try file.readToEndAlloc(allocator, 200000000);
        defer allocator.free(buf);

        const parser = try std.json.parseFromSlice([]BinEntity, allocator, buf, .{ .ignore_unknown_fields = true });
        defer parser.deinit();

        var map: std.StringHashMapUnmanaged(renderer.Renderable) = .{};
        defer map.clearAndFree(allocator);

        var arr: std.ArrayListUnmanaged(entity.Entity) = .{};
        for (parser.value) |e| {
            if (e.path) |p| {
                var renderable: renderer.Renderable = map.get(p[0..p.len]) orelse blk: {
                    const val = switch (e.renderable.?) {
                        .Flat => renderer.Renderable{ .Flat = try renderer.Flat.init(p)},
                        .Stacked => renderer.Renderable{.Stacked = try renderer.Stacked.init(p)},
                    };
                    try map.put(allocator, p[0..p.len], val);
                    break :blk val;
                };

                renderable.set_position(e.position.?);
                _ = try arr.append(allocator, .{
                    .archetype = e.archetype,
                    .collision = e.collision,
                    .renderable = renderable,
                });
            }
        }

        return arr.toOwnedSlice(allocator);
    }

    pub fn get_traction(self: Self, abs_position: rl.Vector2) Traction {
        const img_width = self.physics_image.width;
        const img_height = self.physics_image.height;

        const px: i32 = @intFromFloat(abs_position.x);
        const py: i32 = @intFromFloat(abs_position.y);

        if (px < 0 or py < 0 or px >= img_width or py >= img_height) return .Offroad;
        return .from_pixel(self.physics_image.getColor(px, py));
    }

    pub fn draw(self: Self, shader: rl.Shader) void {
        shader.activate();
        const texture = self.intermediate_texture.texture;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_tex_height"), &texture.height, .int);
        texture.drawPro(.{ .x = 0, .y = 0, .width = 720, .height = -480 }, .{ .x = 0, .y = 0, .width = 720, .height = 480 }, .init(0, 0), 0, .white);
        shader.deactivate();
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.startup_entities);
        self.graphics_texture.unload();
        self.physics_image.unload();
    }

    pub fn save(self: *Self, entities: []entity.Entity, allocator: std.mem.Allocator, comptime directory: []const u8) !void {
        self.startup_entities = entities;

        const entity_file = try std.fs.cwd().createFile(levels_path ++ directory ++ "/entities", .{});
        defer entity_file.close();

        var arr: std.ArrayListUnmanaged(BinEntity) = .{};
        for (entities) |e| {
            _ = try arr.append(allocator, .{
                .collision = e.collision,
                .path = if (e.renderable) |renderable| switch (renderable) {
                    .Stacked => |sprite| sprite.path,
                    .Flat => |sprite| sprite.path,
                } else null,
                .position = if (e.renderable) |renderable| switch (renderable) {
                    .Stacked => |sprite| sprite.position,
                    .Flat => |sprite| sprite.position,
                } else null,
                .renderable  = if (e.renderable) |renderable| switch (renderable) {
                    .Stacked => |_| .Stacked,
                    .Flat => |_| .Flat,
                } else null,
                .archetype = e.archetype,
            });
        }
        try std.json.stringify(arr.items, .{}, entity_file.writer());

        const metadata_file = try std.fs.cwd().createFile(levels_path ++ directory ++ "/metadata", .{});
        defer metadata_file.close();
        try std.json.stringify(self.metadata, .{}, metadata_file.writer());
    }
};

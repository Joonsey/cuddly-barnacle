const std = @import("std");
const rl = @import("raylib");
const renderer = @import("renderer.zig");
const entity = @import("entity.zig");
const prefab = @import("prefabs.zig");


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

pub const Checkpoint = struct {
    position: rl.Vector2,
    radius: f32,
};

pub const Finish = struct {
    left: rl.Vector2,
    right: rl.Vector2,

    const Self = @This();
    pub fn get_spawn(self: Self, i: usize) rl.Vector2 {
        const center = rl.Vector2{
            .x = (self.left.x + self.right.x) * 0.5,
            .y = (self.left.y + self.right.y) * 0.5,
        };

        const max_back_offset = 75;

        const dir = self.right.subtract(self.left).normalize();

        const perp = rl.Vector2{ .x = -dir.y, .y = dir.x };

        const back = rl.Vector2{ .x = -dir.x, .y = -dir.y };

        const spacing_side: f32 = 22.0; // pixels between cars side by side
        const spacing_back: f32 = 22.0; // pixels between rows

        const side_index: f32 = @as(f32, @floatFromInt(i % 2)) * 2.0 - 1.0; // -1, 1, -1, 1...
        const side_offset = back.scale(side_index * spacing_side * @as(f32, @floatFromInt(i / 2)));

        const back_offset = perp.scale(@mod(spacing_back * @as(f32, @floatFromInt(i / 2)), max_back_offset));

        return center.add(side_offset.add(back_offset));
    }

    pub fn get_direction(self: Self) f32 {
        const dir = self.right.subtract(self.left).normalize();
        // idk what is a more ergonomic solution
        // i just offset by a quarter radian
        return std.math.atan2(dir.y, dir.x) - std.math.pi * 0.5;
    }

    pub fn is_intersecting(self: Self, position: rl.Vector2, radius: f32) bool {
        const a = self.left;
        const b = self.right;

        // Vector from A to B
        const ab = b.subtract(a);
        const ab_length = ab.length();

        // Vector from A to circle center
        const ac = position.subtract(a);

        // Project AC onto AB to find the closest point on the line segment
        const ab_dir = ab.scale(1.0 / ab_length);
        const proj = ac.dotProduct(ab_dir);
        const t = @max(0.0, @min(proj, ab_length)); // Clamp to [0, length]

        const closest = a.add(ab_dir.scale(t));

        // Distance from circle center to closest point
        const dist_sq = position.subtract(closest).lengthSqr();

        return dist_sq <= radius * radius;

    }
};

pub const Level = struct {
    physics_image: rl.Image,
    graphics_texture: rl.Texture,
    intermediate_texture: rl.RenderTexture,
    metadata: Metadata,

    startup_entities: []entity.Entity,
    checkpoints: []Checkpoint,
    finish: Finish,

    const BinEntity = struct {
        transform: entity.Transform,
        prefab: prefab.Prefab,
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
            .checkpoints = try load_checkpoints_from_file(levels_path ++ directory ++ "/checkpoints", allocator),
            .finish = try load_finish_from_file(levels_path ++ directory ++ "/finish", allocator),
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

    fn load_checkpoints_from_file(path: []const u8, allocator: std.mem.Allocator) ![]Checkpoint {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const buf = try file.readToEndAlloc(allocator, 200000000);
        defer allocator.free(buf);

        const parser = try std.json.parseFromSlice([]Checkpoint, allocator, buf, .{ .ignore_unknown_fields = true });
        defer parser.deinit();

        return try allocator.dupe(Checkpoint, parser.value);
    }

    fn load_finish_from_file(path: []const u8, allocator: std.mem.Allocator) !Finish {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const buf = try file.readToEndAlloc(allocator, 200000000);
        defer allocator.free(buf);

        const parser = try std.json.parseFromSlice(Finish , allocator, buf, .{ .ignore_unknown_fields = true });
        defer parser.deinit();

        return parser.value;
    }

    fn load_entities_from_file(path: []const u8, allocator: std.mem.Allocator) ![]entity.Entity {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const buf = try file.readToEndAlloc(allocator, 200000000);
        defer allocator.free(buf);

        const parser = try std.json.parseFromSlice([]BinEntity, allocator, buf, .{ .ignore_unknown_fields = true });
        defer parser.deinit();

        var arr: std.ArrayListUnmanaged(entity.Entity) = .{};
        for (parser.value) |e| {
            var ent = prefab.get(e.prefab);
            ent.transform = e.transform;

            try arr.append(allocator, ent);
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

    pub fn draw(self: Self, shader: rl.Shader, camera: renderer.Camera) void {
        shader.activate();
        const texture = self.intermediate_texture.texture;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_tex_height"), &texture.height, .int);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_tex_width"), &texture.width, .int);

        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_rotation"), &camera.rotation, .float);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_offset_x"), &camera.position.x, .float);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_offset_y"), &camera.position.y, .float);

        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_time"), &@as(f32, @floatCast(rl.getTime())), .float);
        texture.drawPro(.{ .x = 0, .y = 0, .width = 720, .height = -480 }, .{ .x = 0, .y = 0, .width = 720, .height = 480 }, .init(0, 0), 0, .white);
        shader.deactivate();
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.startup_entities);
        allocator.free(self.checkpoints);
        self.graphics_texture.unload();
        self.physics_image.unload();
    }

    pub fn save(self: *Self, entities: []entity.Entity, checkpoints: []Checkpoint, finish: Finish, allocator: std.mem.Allocator, comptime directory: []const u8) !void {
        allocator.free(self.startup_entities);
        self.startup_entities = try allocator.dupe(entity.Entity, entities);

        allocator.free(self.checkpoints);
        self.checkpoints = try allocator.dupe(Checkpoint, checkpoints);

        self.finish = finish;

        const checkpoints_file = try std.fs.cwd().createFile(levels_path ++ directory ++ "/checkpoints", .{});
        defer checkpoints_file.close();
        try std.json.stringify(self.checkpoints, .{}, checkpoints_file.writer());

        const entity_file = try std.fs.cwd().createFile(levels_path ++ directory ++ "/entities", .{});
        defer entity_file.close();

        const finish_file = try std.fs.cwd().createFile(levels_path ++ directory ++ "/finish", .{});
        defer finish_file.close();
        try std.json.stringify(self.finish, .{}, finish_file.writer());


        var arr: std.ArrayListUnmanaged(BinEntity) = .{};
        defer arr.deinit(allocator);
        for (entities) |e| {
            if (e.prefab) |pre| {
                _ = try arr.append(allocator, .{
                    .transform = e.transform.?,
                    .prefab = pre,
                });
            }
        }
        try std.json.stringify(arr.items, .{}, entity_file.writer());

        const metadata_file = try std.fs.cwd().createFile(levels_path ++ directory ++ "/metadata", .{});
        defer metadata_file.close();
        try std.json.stringify(self.metadata, .{}, metadata_file.writer());
    }
};

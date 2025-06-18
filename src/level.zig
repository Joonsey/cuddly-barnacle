const std = @import("std");
const rl = @import("raylib");
const renderer = @import("renderer.zig");

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
    metadata: Metadata,

    const Self = @This();
    pub fn init(comptime directory: []const u8) !Self {
        const levels_path = "assets/levels/";

        return .{
            .physics_image = try rl.loadImage(levels_path ++ directory ++ "/physics.png"),
            .graphics_texture = try rl.loadTexture(levels_path ++ directory ++ "/graphics.png"),
            .metadata = Metadata.load(levels_path ++ directory ++ "/metadata") catch .{},
        };
    }

    pub fn get_traction(self: Self, abs_position: rl.Vector2) Traction {
        const img_width = self.physics_image.width;
        const img_height = self.physics_image.height;

        const px: i32 = @intFromFloat(abs_position.x);
        const py: i32 = @intFromFloat(abs_position.y);

        if (px < 0 or py < 0 or px >= img_width or py >= img_height) return .Offroad;
        return .from_pixel(self.physics_image.getColor(px, py));
    }

    pub fn draw(self: Self, camera: renderer.Camera) void {
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
    }
};

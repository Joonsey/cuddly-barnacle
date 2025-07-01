const std = @import("std");
const rl = @import("raylib");

const entity = @import("entity.zig");
const assets = @import("assets.zig");

pub const Camera = struct {
    position: rl.Vector2,
    screen_offset: rl.Vector2,
    render_dimensions: rl.Vector2,
    rotation: f32,

    const Self = @This();
    pub fn init(render_width: f32, render_height: f32) Self {
        return .{
            .position = .{ .x = 0, .y = 0 },
            .screen_offset = .{ .x = render_width / 2, .y = render_height * 0.8 },
            .render_dimensions = .{ .x = render_width, .y = render_height },
            .rotation = 0,
        };
    }

    pub fn target(self: *Self, target_pos: rl.Vector2) void {
        const coefficient = 10.0;
        self.position.x += (target_pos.x - self.position.x) / coefficient;
        self.position.y += (target_pos.y - self.position.y) / coefficient;
    }

    pub fn get_relative_position(self: Self, abs_position: rl.Vector2) rl.Vector2 {
        const delta = abs_position.subtract(self.position);
        const cos_r = @cos(-self.rotation);
        const sin_r = @sin(-self.rotation);

        const rotated: rl.Vector2 = .{
            .x = delta.x * cos_r - delta.y * sin_r,
            .y = delta.x * sin_r + delta.y * cos_r,
        };

        return rotated.add(self.screen_offset);
    }

    pub fn apply_uniforms(self: Self, shader: rl.Shader) void {
        const camera = self;
        const camera_rotation = camera.rotation;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_rotation"), &camera_rotation, .float);
        const camera_position_x: f32 = camera.position.x;
        const camera_position_y: f32 = camera.position.y;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_offset_x"), &camera_position_x, .float);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_offset_y"), &camera_position_y, .float);

        const camera_screen_offset_x = camera.render_dimensions.x - camera.screen_offset.x;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_screen_offset_x"), &camera_screen_offset_x, .float);
        const camera_screen_offset_y = camera.render_dimensions.y - camera.screen_offset.y;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_screen_offset_y"), &camera_screen_offset_y, .float);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_render_width"), &camera_position_y, .float);
    }

    pub fn get_absolute_position(self: Self, relative_position: rl.Vector2) rl.Vector2 {
        const delta = relative_position.subtract(self.screen_offset);
        const cos_r = @cos(self.rotation);
        const sin_r = @sin(self.rotation);

        const rotated: rl.Vector2 = .{
            .x = delta.x * cos_r - delta.y * sin_r,
            .y = delta.x * sin_r + delta.y * cos_r,
        };

        return self.position.add(rotated);
    }

    pub fn is_out_of_bounds(self: Self, abs_position: rl.Vector2) bool {
        const relative_pos = self.get_relative_position(abs_position);

        const render_box = rl.Rectangle.init(0, 0, self.render_dimensions.x, self.render_dimensions.y);

        const generosity = 100;
        const arg_box = rl.Rectangle.init(relative_pos.x - generosity, relative_pos.y - generosity, generosity * 2, generosity * 2);

        return !render_box.checkCollision(arg_box);
    }
};

pub const Rendertypes = enum {
    Stacked,
    Flat,
};

pub const Renderable = union(Rendertypes) {
    Stacked: Stacked,
    Flat: Flat,

    const Self = @This();
};

pub const Flat = struct {
    texture: rl.Texture,
    color: rl.Color = .white,

    const Self = @This();
    pub fn init(path: [:0]const u8) !Self {
        return .{
            .texture = try rl.loadTexture(path),
        };
    }

    pub fn copy(self: Self) Self {
        return .{
            .texture = self.texture,
        };
    }

    pub fn draw(self: Self, camera: Camera, transform: entity.Transform) void {
        const position = transform.position;
        const rotation = transform.rotation;
        const relative_pos = camera.get_relative_position(position);

        const texture = self.texture;
        const f_width: f32 = @floatFromInt(texture.width);
        const f_height: f32 = @floatFromInt(texture.height);
        texture.drawPro(
            .{ .x = 0, .y = 0, .width = f_width, .height = f_height },
            .{ .x = relative_pos.x, .y = relative_pos.y - transform.height, .width = f_width, .height = f_height },
            .{ .x = f_width / 2, .y = f_height / 2 },
            std.math.radiansToDegrees(rotation - camera.rotation),
            self.color,
        );
    }
};
pub const Stacked = struct {
    texture: rl.Texture,
    color: rl.Color = .white,

    const Self = @This();
    pub fn init(path: [:0]const u8) !Self {
        return .{ .texture = try rl.loadTexture(path) };
    }

    pub fn load_from_asset(asset: assets.Asset) !Self {
        const image = try rl.loadImageFromMemory(".png", assets.get(asset));
        defer image.unload();
        return .{ .texture = try image.toTexture() };
    }

    pub fn copy(self: Self) Self {
        return .{
            .texture = self.texture,
        };
    }

    // TODO cache this, i can draw more than 7000 without going below 70 fps
    // but maybe want to consider this at some point however
    pub fn draw(self: Self, camera: Camera, transform: entity.Transform) void {
        const relative_pos = camera.get_relative_position(transform.position);
        const rotation = transform.rotation;

        const texture = self.texture;
        const width = texture.width;
        const rows: usize = @intCast(@divTrunc(texture.height, width));
        const f_width: f32 = @floatFromInt(width);
        for (0..rows) |i| {
            const f_inverse_i: f32 = @floatFromInt(rows - (i + 1));
            const f_i: f32 = @floatFromInt(i);
            texture.drawPro(
                .{ .x = 0, .y = f_inverse_i * f_width, .width = f_width, .height = f_width },
                .{ .x = relative_pos.x, .y = relative_pos.y - f_i - transform.height, .width = f_width, .height = f_width },
                .{ .x = f_width / 2, .y = f_width / 2 },
                std.math.radiansToDegrees(rotation - camera.rotation),
                self.color,
            );
        }
    }

    pub fn draw_raw(self: Self, pos: rl.Vector2, rotation: f32) void {
        const texture = self.texture;
        const width = texture.width;
        const rows: usize = @intCast(@divTrunc(texture.height, width));
        const f_width: f32 = @floatFromInt(width);
        for (0..rows) |i| {
            const f_inverse_i: f32 = @floatFromInt(rows - (i + 1));
            const f_i: f32 = @floatFromInt(i);
            texture.drawPro(
                .{ .x = 0, .y = f_inverse_i * f_width, .width = f_width, .height = f_width },
                .{ .x = pos.x, .y = pos.y - f_i, .width = f_width, .height = f_width },
                .{ .x = f_width / 2, .y = f_width / 2 },
                std.math.radiansToDegrees(rotation),
                self.color,
            );
        }
    }
};
